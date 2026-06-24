pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- tunnel runner
-- by claude + you

-- per-level character. gemp=gem chance, dhp=drone hp, fire=drones shoot,
-- dturn=homing sharpness, dspd=approach speed, mw=mountain arc half-width,
-- mh=mountain height frac, mlen=ridge depth-length (longer = its arc stays
-- blocked longer as the whole thing flies past), si/wi/di=intervals, boss=.
-- cols = ring gradient {far..near}, glow = vanishing point, rib = spokes.
levels={
 {name="outer conduit", gemp=0.34, dhp=3, fire=false, dturn=1.0, dspd=1.0,
  mw=0.055, mh=0.55, mlen=2,  si=26, wi=150, di=220, boss="guardian",
  cols={1,13,12,6}, glow=12, rib=1},      -- cold blue
 {name="toll relay",    gemp=0.34, dhp=3, fire=true,  dturn=0.5, dspd=0.7,
  mw=0.11,  mh=0.85, mlen=18, si=22, wi=120, di=170, boss="warden",
  cols={1,3,11,11}, glow=11, rib=3},      -- toxic green
 {name="cargo spur",    gemp=0.32, dhp=3, fire=true,  dturn=0.6, dspd=0.75,
  mw=0.13,  mh=0.9,  mlen=44, si=20, wi=105, di=150, boss="railer",
  cols={2,13,14,14}, glow=14, rib=2},     -- magenta
 {name="reactor spine", gemp=0.30, dhp=4, fire=true,  dturn=0.7, dspd=0.8,
  mw=0.15,  mh=1.0,  mlen=54, si=18, wi=95,  di=135, boss="reactor",
  cols={1,4,9,10},  glow=9,  rib=4},      -- molten orange
 {name="core vault",    gemp=0.30, dhp=4, fire=true,  dturn=0.8, dspd=0.85,
  mw=0.17,  mh=1.0,  mlen=64, si=16, wi=85,  di=120, boss="heart",
  cols={0,5,6,7},   glow=6,  rib=5},      -- steel void
}
function lvl() return levels[levidx or min(zone,#levels)] end

-- normal run = levels in order; new game+ = randomized, never repeating
-- the current level back-to-back (offset 1..#levels-1 guarantees a change)
function pick_level()
 if ngplus>0 then levidx=(levidx+flr(rnd(#levels-1)))%#levels+1
 else levidx=min(zone,#levels) end
end

function _init()
 cx,cy=64,64
 f=90      -- focal length
 zp=12     -- ship plane depth
 best=0
 ngplus=0   -- new game+ count (persists across runs)
 fire_down=false
 inv=false  -- invincibility cheat (pause-menu toggle)
 dbg=false  -- debug unwrap overlay
 menuitem(1,"invincible: off",toggle_inv)
 menuitem(2,"debug: off",toggle_dbg)
 music(0)  -- start bg loop
 reset_game()
 state="title"
end

function toggle_inv()
 inv=not inv
 menuitem(1,"invincible: "..(inv and "on" or "off"))
 return true  -- keep the pause menu open after toggling
end

function toggle_dbg()
 dbg=not dbg
 menuitem(2,"debug: "..(dbg and "on" or "off"))
 return true
end

function reset_game()
 pa=0           -- ship angle around the rim (0..1 turn)
 pr=7.1         -- ship orbit radius
 score=0
 lives=3
 rt=8.0         -- tunnel world radius
 minrt=2.6
 objs={}
 bolts={}
 ebolts={}
 pops={}
 energy=40        -- weapon charge (from gems)
 firecd=0
 kills=0          -- enemies blasted this sector
 gemct=0          -- crystals collected this sector
 ringz={}
 for i=1,8 do ringz[i]=i*13 end
 rot=0
 shake=0
 spawn_t=20
 btimer=120
 dtimer=240
 zone=1
 pick_level()
 zonelen=1400     -- frames of descent per zone
 depth=0          -- 0..100 progress to the gate
 zbanner=90
 gatetimer=0
 inboss=false
 boss=nil
 flow=1
 t=0
 flash=0
end

-->8
-- update

function _update60()
 t+=1
 -- rising edge of fire (no autorepeat) so holding z/x can't skip dialogs
 local fd=btn(4) or btn(5)
 fire_edge=fd and not fire_down
 fire_down=fd
 -- tunnel forward-motion eases to a near-stop at the gate/boss
 local ft=(state=="gate" or inboss) and 0.08 or 1
 flow+=(ft-flow)*0.05
 if state=="title" then
  rot+=0.003
  move_rings(1.0)
  if fire_edge then
   sfx(3) reset_game() state="brief"
  end
 elseif state=="play" then
  update_play()
 elseif state=="gate" then
  gatetimer-=1
  rot+=0.0012+0.0035*flow
  move_rings(1.4*flow)       -- coast to a stop
  if gatetimer<=0 then start_boss() end
 elseif state=="bossdead" then
  deadtmr-=1
  rot+=0.01 move_rings(1.5)
  if shake>0 then shake-=1 end
  if flash>0 then flash-=1 end
  if deadtmr<=0 then
   if deadfinal then state="victory" t=0
   else debrief_cap=false state="debrief" t=0 end
  end
 elseif state=="brief" then
  rot+=0.004 move_rings(1.0)
  if fire_edge then sfx(3) zbanner=0 state="play" end
 elseif state=="debrief" then
  rot+=0.004 move_rings(1.0)
  if fire_edge then sfx(3) next_zone() end
 elseif state=="victory" then
  rot+=0.003 move_rings(0.8)
  if t>50 and (fire_edge) then
   sfx(3) ngplus+=1 reset_game() state="brief"  -- TODO: new game+ modifiers
  end
 elseif state=="over" then
  rot+=0.002
  move_rings(0.5)
  if t>30 and (fire_edge) then
   sfx(3) reset_game() state="brief"
  end
 end
end

function move_rings(spd)
 for i=1,#ringz do
  ringz[i]-=spd
  if ringz[i]<=2 then ringz[i]+=104 end
 end
end

function update_play()
 if zbanner>0 then zbanner-=1 end
 local d=min(9,(8-rt)+(zone-1)*1.2)  -- difficulty rises each zone
 -- descend toward the guild gate (paused during a boss)
 if not inboss then
  depth+=100/zonelen
  if depth>=100 then
   state="gate" gatetimer=150
   objs={} bolts={} ebolts={}
   return
  end
 end
 -- survival score (paused during the boss; the kill pays out instead)
 if not inboss and t%6==0 then score+=1 end
 -- ship orbits the rim (left/right rotate, wraps full circle)
 local asp=0.014
 if btn(0) then pa-=asp end
 if btn(1) then pa+=asp end
 pa%=1
 pr=max(1.2,rt-0.9)        -- orbit radius tracks the shrinking rim
 -- tunnel slowly shrinks (held steady during a boss)
 if not inboss then rt=max(minrt,rt-0.0011) end
 rot+=0.0012+0.0035*flow
 move_rings((1.2+d*0.12)*flow)
 -- spawning
 if inboss then
  update_boss(d)
 else
  local L=lvl()
  local prog=8-rt            -- within-level intensity ramp
  spawn_t-=1
  if spawn_t<=0 then spawn_obj() spawn_t=max(10,L.si-prog*3) end
  btimer-=1
  if btimer<=0 then spawn_wall() btimer=max(50,L.wi-prog*12) end
  dtimer-=1
  if dtimer<=0 then spawn_drone() dtimer=max(70,L.di-prog*16) end
 end
 -- move objects
 local osp=1.0+d*0.18
 for o in all(objs) do
  local oz=o.z
  if o.kind=="drone" then
   o.z-=osp*o.dspd            -- lingering drones approach slower
   if o.flash>0 then o.flash-=1 end
   -- home toward the player (dturn<1 = looser, dumber tracking)
   local turn=(0.003+(1-o.z/110)*0.006)*o.dturn
   local dd=pa-o.ang
   if dd>0.5 then dd-=1 elseif dd<-0.5 then dd+=1 end
   o.ang+=mid(-turn,dd,turn)
   -- fire back at the player
   if o.fire and o.z<100 and o.z>48 then   -- only fire from range (dodge time)
    o.ftmr-=1
    if o.ftmr<=0 then add(ebolts,{ang=o.ang,z=o.z}) o.ftmr=55+rnd(25) end
   end
  elseif o.kind=="fire" then
   o.z-=osp
   o.ang=(o.ang+o.sweep)%1     -- sweeping barrier
  elseif o.kind=="wall" or o.kind=="rail" then
   o.z-=osp                    -- long ridge / rail: flies past, never stops
  else
   o.z-=osp                    -- mine / gem
  end
  -- collision at the player plane
  if o.kind=="wall" or o.kind=="rail" then
   -- dangerous the whole time it's on-screen sweeping past you,
   -- not just while its depth straddles the player plane
   if not o.hit and o.z<=zp and o.z+o.zlen>1 then
    local da=abs(o.ang-pa) da=min(da,1-da)
    if da<o.hw then hit_mine() o.hit=true end
   end
  elseif oz>zp and o.z<=zp then
   local da=abs(o.ang-pa) da=min(da,1-da)
   if o.kind=="fire" then
    if da<o.hw then hit_mine() end
   elseif o.kind=="gem" then
    local sr=pr*(f/zp)
    if da<mid(0.05,11/(6.2832*sr),0.3) then collect(o) o.dead=true end
   else                       -- mine or drone
    local sr=pr*(f/zp)
    if da<mid(0.04,8/(6.2832*sr),0.25) then hit_mine() o.dead=true end
   end
  end
  if o.kind=="wall" or o.kind=="rail" then
   if o.z+o.zlen<=1 then o.dead=true end
  elseif o.z<=1 then o.dead=true end
 end
 for o in all(objs) do
  if o.dead then del(objs,o) end
 end
 -- firing (gems = ammo): hold z/x
 firecd-=1
 if (btn(4) or btn(5)) and firecd<=0 and (inv or energy>=5) then
  add(bolts,{ang=pa,z=zp})
  if not inv then energy-=5 end   -- cheat: infinite ammo
  firecd=7 sfx(6)
 end
 -- bolts travel down the spoke into the tunnel
 for b in all(bolts) do
  b.z+=5
  if b.z>110 then b.dead=true end
  for o in all(objs) do
   if not o.dead then
    local da=abs(b.ang-o.ang) da=min(da,1-da)
    if o.kind=="wall" then
     if da<o.hw and abs(b.z-o.z)<5 then b.dead=true end   -- absorbed by rock
    elseif o.kind=="fire" or o.kind=="rail" then
     -- energy curtain / railgun: indestructible, bolts pass through
    elseif da<0.05 and abs(b.z-o.z)<6 then
     b.dead=true
     local s=f/o.z
     local sx,sy=64+cos(o.ang)*pr*s,64+sin(o.ang)*pr*s
     if o.kind=="drone" then        -- armored: needs 3 hits
      o.hp-=1 o.flash=4 sfx(6)
      if o.hp<=0 then
       o.dead=true score+=40 kills+=1 sfx(1)
       add(pops,{x=sx,y=sy,life=22,txt="+40",col=10})
      end
     elseif o.kind=="gem" then      -- wasted a crystal
      o.dead=true
      add(pops,{x=sx,y=sy,life=18,txt="lost",col=5})
     else                          -- killed a mine
      o.dead=true score+=15 kills+=1 sfx(1)
      add(pops,{x=sx,y=sy,life=20,txt="+15",col=10})
     end
    end
   end
  end
  -- bolt reaches the boss core
  if inboss and not b.dead and b.z>=boss.z then
   b.dead=true
   if boss.kind=="reactor" then
    reactor_hit(b.ang)
   else
    local hits
    if boss.kind=="warden" then
     hits = spoke_dist(b.ang)>0.045   -- only through a gap in the shield
    else
     local cda=abs(b.ang-boss.coreang) cda=min(cda,1-cda)
     hits = cda<0.06
    end
    if hits then
     boss.hp-=1 boss.flash=4 sfx(1)
     if boss.hp<=0 then win_boss() end
    end
   end
  end
 end
 for b in all(bolts) do
  if b.dead then del(bolts,b) end
 end
 -- enemy fire travels out to your rim
 for e in all(ebolts) do
  local ez=e.z
  e.z-=3.0
  if ez>zp and e.z<=zp then
   local da=abs(e.ang-pa) da=min(da,1-da)
   if da<0.05 then hit_mine() end
   e.dead=true
  end
  if e.z<=1 then e.dead=true end
 end
 for e in all(ebolts) do if e.dead then del(ebolts,e) end end
 -- popups
 for p in all(pops) do
  p.y-=0.5 p.life-=1
  if p.life<=0 then del(pops,p) end
 end
 if shake>0 then shake-=1 end
 if flash>0 then flash-=1 end
end

function spawn_obj()
 -- half aim at the ship's current angle (committed), half random
 local ang = rnd(1)<0.5 and pa or rnd(1)
 local o={
  ang=ang,
  x=cos(ang)*pr, y=sin(ang)*pr,   -- fixed spoke out to the rim
  z=110, r=0.7, spin=rnd(1),
 }
 o.kind = rnd(1)<lvl().gemp and "gem" or "mine"
 add(objs,o)
end

function next_zone()
 zone+=1
 pick_level()
 depth=0
 kills=0 gemct=0
 zbanner=110
 rt=min(8,rt+1.2)        -- breathing room past the gate
 objs={} bolts={} ebolts={}
 inboss=false boss=nil
 spawn_t=30 btimer=120 dtimer=160
 state="brief"
end

function start_boss()
 state="play"
 inboss=true
 objs={} bolts={} ebolts={}
 local k=lvl().boss
 boss={kind=k, hp=24, maxhp=24, coreang=0, flash=0, z=100,
       c0=rnd(1), cspd=0.0022, crange=0,
       dtmr=50, ftmr=80, gtmr=60}
 if k=="railer" then
  boss.hp=28 boss.maxhp=28        -- tankier
  boss.cspd=0.004                 -- slow full-circle pendulum sweep
  boss.ftmr=70
 elseif k=="warden" then
  boss.hp=30 boss.maxhp=30
  boss.nspoke=5 boss.curspokes=5  -- rotating shield/pinwheel of spokes
  boss.spokeang=0 boss.spokespd=0.004 boss.spokecd=0
  boss.dtmr=130
 elseif k=="reactor" then
  boss.maxhp=28 boss.hp=28
  boss.nodes={}                   -- destroy each node to win
  for i=1,4 do add(boss.nodes,{ang=(i-1)/4,hp=7,alive=true,flash=0}) end
  boss.rrot=0 boss.rspd=0.0035
  boss.pulsetmr=120 boss.beamon=0 boss.spokecd=0 boss.gtmr=90
 elseif k=="heart" then
  boss.hp=36 boss.maxhp=36        -- the finale
  boss.cspd=0.003                 -- exploit point rotates
  boss.atk=0 boss.atmr=90 boss.gtmr=85
 end
end

function boss_gems(n)
 boss.gtmr-=1
 if boss.gtmr<=0 then
  local a=rnd(1)
  add(objs,{kind="gem",ang=a,x=cos(a)*pr,y=sin(a)*pr,z=110,r=0.7,spin=rnd(1)})
  boss.gtmr=n
 end
end

function update_boss(d)
 local p2=boss.hp<=boss.maxhp/2          -- enraged phase
 if boss.flash>0 then boss.flash-=1 end
 if boss.kind=="warden" then update_warden(p2) return end
 if boss.kind=="reactor" then update_reactor(p2) return end
 if boss.kind=="heart" then update_heart(p2) return end
 -- weak-point movement
 if boss.kind=="railer" then
  -- sweeps a full 360, eases to a stop, then reverses
  boss.coreang=(boss.c0+0.5+0.5*sin(t*boss.cspd*(p2 and 1.3 or 1)))%1
 else
  boss.coreang=(boss.coreang+(p2 and 0.005 or 0.0022))%1
 end
 -- drone waves (both)
 boss.dtmr-=1
 if boss.dtmr<=0 then
  spawn_drone()
  boss.dtmr=p2 and 50 or 90
 end
 -- signature attack
 boss.ftmr-=1
 if boss.ftmr<=0 then
  if boss.kind=="railer" then
   fire_rail(p2) boss.ftmr=p2 and 75 or 115
  else
   spawn_fire(p2) boss.ftmr=p2 and 80 or 140
  end
 end
 boss_gems(110)   -- shed crystals so you can keep firing
end

function update_heart(p2)
 boss.coreang=(boss.coreang+boss.cspd*(p2 and 1.6 or 1))%1
 -- COLLAPSE: the more you damage the heart, the tighter the tunnel caves in
 local frac=boss.hp/boss.maxhp
 local target=minrt+(8-minrt)*frac*0.9
 rt=rt+(target-rt)*0.04
 if frac<0.35 and t%24==0 then shake=4 end       -- chamber buckling
 -- escalating arsenal: cycle the Guild's weapons, faster as it dies
 boss.atmr-=1
 if boss.atmr<=0 then
  local a=boss.atk%3
  if a==0 then spawn_fire(p2)
  elseif a==1 then fire_rail(p2)
  else spawn_drone() spawn_drone() end
  boss.atk+=1
  boss.atmr=max(35,(p2 and 55 or 80)-flr((1-frac)*30))
 end
 boss_gems(85)
end

function reactor_alive()
 local n=0
 for nd in all(boss.nodes) do if nd.alive then n+=1 end end
 return n
end

function update_reactor(p2)
 local alive=reactor_alive()
 boss.rrot=(boss.rrot+boss.rspd*(1+(4-alive)*0.3))%1   -- faster as nodes die
 for nd in all(boss.nodes) do if nd.flash>0 then nd.flash-=1 end end
 if boss.spokecd>0 then boss.spokecd-=1 end
 -- overload pulse: all alive nodes fire radial beams at once
 if boss.beamon>0 then
  boss.beamon-=1
  if boss.spokecd<=0 then
   for nd in all(boss.nodes) do
    if nd.alive then
     local da=abs(pa-(nd.ang+boss.rrot)%1) da=min(da,1-da)
     if da<0.05 then hit_mine() boss.spokecd=30 break end
    end
   end
  end
 else
  boss.pulsetmr-=1
  if boss.pulsetmr<=0 then
   boss.beamon=25
   boss.pulsetmr=max(70,150-(4-alive)*22)   -- pulses faster as nodes die
  end
 end
 boss_gems(90)   -- crystals to refuel
end

function reactor_hit(bang)
 for nd in all(boss.nodes) do
  if nd.alive then
   local cda=abs(bang-(nd.ang+boss.rrot)%1) cda=min(cda,1-cda)
   if cda<0.05 then
    nd.hp-=1 nd.flash=4 boss.flash=4 sfx(1)
    if nd.hp<=0 then nd.alive=false end
    break
   end
  end
 end
 local h=0
 for nd in all(boss.nodes) do if nd.alive then h+=nd.hp end end
 boss.hp=h
 if boss.hp<=0 then win_boss() end
end

-- angular distance from `ang` to the nearest pinwheel spoke
function spoke_dist(ang)
 local n=boss.curspokes
 local best=1
 for k=0,n-1 do
  local da=abs(ang-(boss.spokeang+k/n)) da=min(da,1-da)
  if da<best then best=da end
 end
 return best
end

function update_warden(p2)
 boss.curspokes=boss.nspoke+(p2 and 1 or 0)   -- extra blade when enraged
 boss.spokeang=(boss.spokeang+boss.spokespd*(p2 and 1.6 or 1))%1
 if boss.spokecd>0 then boss.spokecd-=1 end
 -- weave hazard: a spoke clips you (brief cooldown so it's one life)
 if boss.spokecd<=0 and spoke_dist(pa)<0.045 then
  hit_mine() boss.spokecd=30
 end
 -- occasional drones + crystals to refuel
 boss.dtmr-=1
 if boss.dtmr<=0 then spawn_drone() boss.dtmr=p2 and 90 or 140 end
 boss_gems(100)
end

function fire_rail(wide)
 -- railgun: spreads across an arc AND is very long in depth (z).
 -- dodge out of its lane, then wait for the whole length to fly past.
 local ang=rnd(1)<0.6 and pa or rnd(1)   -- often aimed at you
 add(objs,{kind="rail", ang=ang, hw=wide and 0.14 or 0.10,
           z=110, zlen=wide and 120 or 90, hit=false})
end

function spawn_fire(wide)
 local dir=rnd(1)<0.5 and 1 or -1
 add(objs,{kind="fire",ang=rnd(1),z=110,
           hw=wide and 0.16 or 0.10,
           sweep=dir*(wide and 0.006 or 0.004)})
end

function win_boss()
 score+=500
 sfx(1)
 inboss=false boss=nil
 objs={} bolts={} ebolts={}
 shake=16 flash=10
 deadfinal=(zone>=#levels and ngplus==0)   -- first run end vs endless
 if deadfinal then score+=1000 best=max(best,score) sfx(3) end
 state="bossdead" deadtmr=80 t=0           -- play the death burst first
end

function zonename()
 return lvl().name
end

function spawn_drone()
 local L=lvl()
 add(objs,{kind="drone",ang=rnd(1),z=110,hp=L.dhp,flash=0,spin=rnd(1),
  fire=L.fire, ftmr=40+rnd(30), dturn=L.dturn, dspd=L.dspd})
end

function spawn_wall()
 local L=lvl()
 local prog=8-rt
 -- a mountain ridge spanning an arc of the wall
 local np=3+flr(rnd(3))      -- 3..5 peaks
 local hs={}
 for i=1,np do hs[i]=0.4+rnd(0.55) end
 add(objs,{
  kind="wall", ang=rnd(1),
  hw=L.mw+rnd(0.05)+prog*0.004, -- arc half-width (wider in later levels)
  mh=L.mh, np=np, hs=hs, z=110,
  zlen=L.mlen, hit=false,       -- depth-length of the ridge
 })
end

function collect(o)
 score+=25
 gemct+=1
 energy=min(100,energy+22)  -- crystal scrap powers the gun
 rt=min(8,rt+0.06)       -- gems give breathing room
 sfx(0)
 local s=f/zp
 add(pops,{x=64+o.x*s,y=64+o.y*s,life=24,txt="+25"})
end

function hit_mine()
 if inv then return end   -- cheat: no damage
 lives-=1
 rt=max(minrt,rt-0.3)
 shake=12 flash=6
 sfx(1)
 if lives<=0 then
  best=max(best,score)
  state="over" t=0
  sfx(2)
 end
end

-->8
-- draw

function _draw()
 if state=="debrief" then draw_debrief() return end
 cls(0)
 local ox,oy=0,0
 if shake>0 then ox=rnd(4)-2 oy=rnd(4)-2 end
 camera(ox,oy)
 draw_tunnel()
 if state=="play" or state=="gate" then
  if inboss then draw_boss() end
  draw_objs() draw_ebolts() draw_bolts() draw_ship()
 elseif state=="bossdead" then
  draw_ship()
 end
 camera()
 if flash>0 then
  for i=0,15 do pal(i,8) end
  rectfill(0,0,127,127,8) pal()
 end
 if state=="title" then
  draw_title()
 elseif state=="brief" then
  draw_brief()
 elseif state=="victory" then
  draw_victory()
 elseif state=="bossdead" then
  draw_bossdead()
 else
  draw_hud()
  if zbanner>0 then draw_banner() end
  if state=="play" and not inboss and depth>80 then draw_warning() end
  if state=="gate" then draw_gate() end
  if state=="over" then draw_over() end
 end
 if dbg then draw_debug() end
end

function ring_col(z)
 if inboss or state=="gate" or state=="bossdead" then   -- danger chamber (red)
  if z>50 then return 2
  elseif z>20 then return 8
  else return 14 end
 end
 local c=lvl().cols
 if z>55 then return c[1]
 elseif z>28 then return c[2]
 elseif z>13 then return c[3]
 else return c[4] end
end

function draw_tunnel()
 local danger=inboss or state=="gate" or state=="bossdead"
 -- vanishing-point glow
 circfill(cx,cy,2+sin(t/120),7)
 circ(cx,cy,4,danger and 8 or lvl().glow)
 -- rotating ribs
 local ribc=danger and 2 or lvl().rib
 for k=0,11 do
  local a=k/12+rot
  local c,s=cos(a),sin(a)
  local rn=rt*f/6
  local rf=rt*f/110
  line(cx+c*rn,cy+s*rn,cx+c*rf,cy+s*rf,ribc)
 end
 -- rings far->near (chamber adds an interleaved set)
 -- in the chamber, skip tiny far rings so they don't pile into a blob
 local rmin=danger and 14 or 0
 for i=1,#ringz do
  local z=ringz[i]
  if z>2 then
   local r=rt*f/z
   if r<210 and r>rmin then circ(cx,cy,r,ring_col(z)) end
  end
  if danger then
   local z2=z+6.5            -- companion ring halfway between
   if z2>2 and z2<118 then
    local r2=rt*f/z2
    if r2<210 and r2>rmin then circ(cx,cy,r2,ring_col(z2)) end
   end
  end
 end
end

function draw_objs()
 -- array is near->far, draw far first
 for i=#objs,1,-1 do
  local o=objs[i]
  local z=o.z
  -- walls/rails stay drawn while ANY part (far edge) is on screen,
  -- so the visual lasts exactly as long as the threat does
  local vis
  if o.kind=="wall" or o.kind=="rail" then vis=o.z+o.zlen>1
  else vis=z>1 end
  if vis then
   if o.kind=="wall" then
    draw_wall(o)
   elseif o.kind=="rail" then
    draw_rail(o)
   elseif o.kind=="fire" then
    draw_fire(o)
   elseif o.kind=="drone" then
    draw_drone(o)
   else
    local s=f/z
    local x,y=64+o.x*s,64+o.y*s
    local r=o.r*s
    if o.kind=="gem" then draw_gem(x,y,r)
    else draw_mine(x,y,r,o) end
   end
  end
 end
 for p in all(pops) do
  print(p.txt,p.x-4,p.y,p.col or (p.life%4<2 and 7 or 11))
 end
end

function fill_diamond(x,y,r,col)
 r=flr(mid(1,r,46))
 for i=0,r do
  local w=r-i
  rectfill(x-w,y-i,x+w,y-i,col)
  rectfill(x-w,y+i,x+w,y+i,col)
 end
end

function draw_gem(x,y,r)
 fill_diamond(x,y,r,12)
 if r>2 then
  fill_diamond(x,y-r*0.2,r*0.5,7)
  pset(x-r*0.3,y-r*0.3,7)
 end
end

-- railgun beam: an arc-wide energy curtain extruded very long in depth
function draw_rail(o)
 local nsl=9
 local a1=o.ang-o.hw
 local aw=o.hw*2
 for sl=nsl,1,-1 do
  local z=o.z+o.zlen*((sl-1)/(nsl-1))
  if z>1.5 then
   local s=f/z
   local r0=rt*s              -- outer (rim)
   local r1=rt*0.12*s         -- inner (near center)
   local col=({12,7,12,6,7,12})[(sl+flr(t*0.6))%6+1]  -- electric flicker
   for k=0,10 do
    local a=a1+aw*(k/10)
    local c,sn=cos(a),sin(a)
    line(64+c*r1,64+sn*r1, 64+c*r0,64+sn*r0, col)
   end
  end
 end
end

function draw_fire(o)
 local s=f/o.z
 local n=7
 local stp=(o.hw*2)/n
 local a1=o.ang-o.hw
 local h=1.7
 for i=0,n-1 do
  local al,ar=a1+stp*i,a1+stp*(i+1)
  local cl,sl=cos(al),sin(al)
  local cr,sr=cos(ar),sin(ar)
  local olx,oly=64+cl*rt*s,64+sl*rt*s
  local orx,ory=64+cr*rt*s,64+sr*rt*s
  local ilx,ily=64+cl*(rt-h)*s,64+sl*(rt-h)*s
  local irx,iry=64+cr*(rt-h)*s,64+sr*(rt-h)*s
  local col=(i+flr(t*0.6))%2==0 and 9 or 10
  trifill(olx,oly,orx,ory,irx,iry,col)
  trifill(olx,oly,irx,iry,ilx,ily,col)
  line(ilx,ily,irx,iry,t%3==0 and 7 or 10)
 end
end

function draw_boss_railer()
 local hot=boss.flash>0
 local p2=boss.hp<=boss.maxhp/2
 local x,y=64,64
 local rr=30
 local ca=boss.coreang
 local tipx=x+cos(ca)*rr*0.72
 local tipy=y+sin(ca)*rr*0.72
 -- industrial armor ring + struts (corporate yellow/gray)
 for k=0,7 do
  local a=k/8
  local c,s=cos(a),sin(a)
  line(x+c*rr*0.5,y+s*rr*0.5,x+c*rr,y+s*rr,hot and 7 or (p2 and 9 or 5))
 end
 circ(x,y,rr,hot and 7 or (p2 and 9 or 6))
 circ(x,y,rr-5,p2 and 4 or 5)
 -- rail barrel: a wedge aiming at the swinging weak core
 local px=cos(ca+0.25)*4
 local py=sin(ca+0.25)*4
 trifill(x+px,y+py,x-px,y-py,tipx,tipy,hot and 7 or (p2 and 8 or 5))
 line(x,y,tipx,tipy,10)        -- glowing bore
 -- swinging weak core at the barrel tip (shoot this)
 local pul=2+sin(t/(p2 and 10 or 22))
 circfill(tipx,tipy,5+pul,p2 and 8 or 9)
 circfill(tipx,tipy,3+pul,hot and 7 or 10)
 circfill(tipx,tipy,1+pul*0.5,7)
 -- hub
 circfill(x,y,4,hot and 7 or (p2 and 8 or 5))
 pset(x,y,7)
end

function draw_boss_warden()
 local hot=boss.flash>0
 local p2=boss.hp<=boss.maxhp/2
 local x,y=64,64
 local n=boss.curspokes
 local hw=0.045                 -- blade half-width (matches collision)
 local r0=6
 local r1=rt*(f/zp)            -- out to the rim
 local col=hot and 7 or (p2 and 8 or 9)
 for k=0,n-1 do
  local a=boss.spokeang+k/n
  local apx,apy=x+cos(a)*r0,y+sin(a)*r0
  local blx,bly=x+cos(a-hw)*r1,y+sin(a-hw)*r1
  local brx,bry=x+cos(a+hw)*r1,y+sin(a+hw)*r1
  trifill(apx,apy,blx,bly,brx,bry,col)             -- blade
  line(x+cos(a)*r0,y+sin(a)*r0,x+cos(a)*r1,y+sin(a)*r1,7)  -- hot spine
  circfill(x+cos(a)*r1,y+sin(a)*r1,2,hot and 7 or 10)      -- tip
 end
 -- exposed weak core (shoot through a gap)
 local pul=2+sin(t/18)
 circfill(x,y,5+pul,hot and 7 or 2)
 circfill(x,y,3+pul,p2 and 8 or 11)
 circfill(x,y,1+pul*0.5,7)
end

function draw_boss_reactor()
 local x,y=64,64
 local rnode=18
 local r1=rt*(f/zp)
 local charging=boss.beamon<=0 and boss.pulsetmr<28   -- telegraph
 for nd in all(boss.nodes) do
  if nd.alive then
   local na=(nd.ang+boss.rrot)%1
   local nx,ny=x+cos(na)*rnode,y+sin(na)*rnode
   if boss.beamon>0 then
    -- active beam wedge (width matches collision)
    local hw=0.05
    trifill(nx,ny,x+cos(na-hw)*r1,y+sin(na-hw)*r1,
                  x+cos(na+hw)*r1,y+sin(na+hw)*r1, t%2==0 and 10 or 9)
    line(nx,ny,x+cos(na)*r1,y+sin(na)*r1,7)
   elseif charging and t%4<2 then
    line(nx,ny,x+cos(na)*r1,y+sin(na)*r1,8)        -- blinking warning
   end
   line(x,y,nx,ny,5)                                -- spine to core
   local nf=nd.flash>0
   circfill(nx,ny,4,nf and 7 or 9)
   circfill(nx,ny,2.5,nf and 7 or 10)
   pset(nx,ny,7)
  end
 end
 circfill(x,y,3,2) circfill(x,y,1,8)               -- core hub
end

function draw_boss_heart()
 local hot=boss.flash>0
 local p2=boss.hp<=boss.maxhp/2
 local x,y=64,64
 local frac=boss.hp/boss.maxhp
 local pul=sin(t/18)*2
 local rr=flr(24+pul)
 -- crystal body (layered facets)
 fill_diamond(x,y,rr,    hot and 7 or 2)
 fill_diamond(x,y,rr-3,  hot and 7 or (p2 and 8 or 14))
 fill_diamond(x,y,rr-9,  hot and 7 or 8)
 fill_diamond(x,y,rr-15, 2)
 line(x-rr,y,x,y-rr,7) line(x,y-rr,x+rr,y,7)   -- top facets lit
 -- cracks spread as the heart fails
 for i=1,flr((1-frac)*7) do
  local a=i*0.137+0.05
  line(x,y,x+cos(a)*rr,y+sin(a)*rr,0)
 end
 -- rotating exploit point (shoot this)
 local ca=boss.coreang
 local cx2=x+cos(ca)*(rr*0.58)
 local cy2=y+sin(ca)*(rr*0.58)
 local cp=2+sin(t/12)
 circfill(cx2,cy2,4+cp,hot and 7 or 11)
 circfill(cx2,cy2,2+cp,7)
 -- failing core
 circfill(x,y,3+pul,hot and 7 or 8)
 pset(x,y,7)
end

function draw_boss()
 if boss.kind=="heart" then draw_boss_heart() return end
 if boss.kind=="reactor" then draw_boss_reactor() return end
 if boss.kind=="warden" then draw_boss_warden() return end
 if boss.kind=="railer" then draw_boss_railer() return end
 local hot=boss.flash>0
 local p2=boss.hp<=boss.maxhp/2
 local rr=30
 local x,y=64,64
 -- open armor rings (tunnel floats through, no opaque fill)
 circ(x,y,rr,hot and 7 or (p2 and 8 or 5))
 circ(x,y,rr-4,p2 and 2 or 6)
 -- outer struts: fast & red in phase 2
 local spin=t*(p2 and 0.03 or 0.007)
 local sc=hot and 7 or (p2 and 8 or 6)
 for k=0,5 do
  local a=k/6+spin
  local c,s=cos(a),sin(a)
  line(x+c*rr*0.42,y+s*rr*0.42,x+c*rr,y+s*rr,sc)
  circfill(x+c*rr,y+s*rr,1.5,p2 and 14 or 13)
 end
 -- orbiting weak core (shoot this) - pulses faster in phase 2
 local ca=boss.coreang
 local cx2=x+cos(ca)*(rr*0.5)
 local cy2=y+sin(ca)*(rr*0.5)
 local pul=2+sin(t/(p2 and 12 or 30))
 circfill(cx2,cy2,5+pul,p2 and 2 or 8)
 circfill(cx2,cy2,3+pul,hot and 7 or (p2 and 8 or 10))
 circfill(cx2,cy2,1+pul*0.5,7)
 -- small central hub
 circfill(x,y,3,hot and 7 or (p2 and 8 or 2))
 pset(x,y,7)
end

function draw_drone(o)
 local s=f/o.z
 local x=64+cos(o.ang)*pr*s
 local y=64+sin(o.ang)*pr*s
 local r=mid(1.5,0.95*s,28)
 local hot=o.flash>0
 -- rotating claws
 local sp=o.spin+t*0.02
 for k=0,3 do
  local a=sp+k/4
  local cx2,cy2=x+cos(a)*r*1.35,y+sin(a)*r*1.35
  line(x,y,cx2,cy2,5)
  circfill(cx2,cy2,max(1,r*0.22),hot and 7 or 13)
 end
 -- armored hull
 circfill(x,y,r,hot and 7 or 6)
 circfill(x,y,r*0.72,5)
 -- red scanner eye, staring outward at the player
 local ex=x+cos(o.ang)*r*0.25
 local ey=y+sin(o.ang)*r*0.25
 circfill(ex,ey,r*0.42,hot and 7 or 8)
 circfill(ex,ey,r*0.22,hot and 7 or 14)
 -- hp pips above the hull
 if r>4 then
  for i=1,o.hp do pset(x-2+i*2,y-r-2,11) end
 end
end

function draw_bolts()
 for b in all(bolts) do
  local s1=f/b.z
  local s0=f/max(zp,b.z-7)
  local c,s=cos(b.ang),sin(b.ang)
  local x1,y1=64+c*pr*s1,64+s*pr*s1
  local x0,y0=64+c*pr*s0,64+s*pr*s0
  line(x0,y0,x1,y1,12)     -- plasma trail
  circfill(x1,y1,1.2,7)    -- hot head
  pset(x1,y1,10)
 end
end

function draw_ebolts()
 for e in all(ebolts) do
  local s=f/e.z
  local x=64+cos(e.ang)*pr*s
  local y=64+sin(e.ang)*pr*s
  circfill(x,y,1.6,8)      -- red enemy plasma
  circfill(x,y,0.8,9)
  pset(x,y,10)
 end
end

-- a long ridge drawn as a solid prism extruded from the near face (z0)
-- down its depth to the far face (z1). each peak = base-left, base-right,
-- inward apex; the slopes are swept in depth and filled.
function draw_wall(o)
 local z0=max(2.5,o.z)             -- near face (clamped so it can't blow up)
 local z1=o.z+o.zlen               -- far face
 if z1<=1 then return end
 local s0,s1=f/z0,f/z1
 local h=rt*o.mh
 local a1=o.ang-o.hw
 local stp=(o.hw*2)/o.np
 -- pass 1: extruded body (left & right slopes swept down the tunnel)
 for i=1,o.np do
  local bl=a1+stp*(i-1)
  local br=a1+stp*i
  local am=(bl+br)*0.5
  local rh=rt-h*o.hs[i]
  local lnx,lny=64+cos(bl)*rt*s0,64+sin(bl)*rt*s0
  local rnx,rny=64+cos(br)*rt*s0,64+sin(br)*rt*s0
  local anx,any=64+cos(am)*rh*s0,64+sin(am)*rh*s0
  local lfx,lfy=64+cos(bl)*rt*s1,64+sin(bl)*rt*s1
  local rfx,rfy=64+cos(br)*rt*s1,64+sin(br)*rt*s1
  local afx,afy=64+cos(am)*rh*s1,64+sin(am)*rh*s1
  trifill(lnx,lny,anx,any,afx,afy,4)   -- left slope (lit)
  trifill(lnx,lny,afx,afy,lfx,lfy,4)
  trifill(rnx,rny,anx,any,afx,afy,5)   -- right slope (shadow)
  trifill(rnx,rny,afx,afy,rfx,rfy,5)
  line(anx,any,afx,afy,15)             -- crest ridgeline
 end
 -- pass 2: near faces on top, with edges + snow
 for i=1,o.np do
  local bl=a1+stp*(i-1)
  local br=a1+stp*i
  local am=(bl+br)*0.5
  local rh=rt-h*o.hs[i]
  local lnx,lny=64+cos(bl)*rt*s0,64+sin(bl)*rt*s0
  local rnx,rny=64+cos(br)*rt*s0,64+sin(br)*rt*s0
  local anx,any=64+cos(am)*rh*s0,64+sin(am)*rh*s0
  trifill(lnx,lny,rnx,rny,anx,any,4)
  line(lnx,lny,anx,any,15)
  line(rnx,rny,anx,any,2)
  if o.hs[i]>0.72 then
   trifill(anx,any,anx+(lnx-anx)*0.32,any+(lny-any)*0.32,
                   anx+(rnx-anx)*0.32,any+(rny-any)*0.32,7)
  end
 end
end

function draw_mine(x,y,r,o)
 r=mid(1,r,40)
 local sp=o.spin+t*0.003
 for k=0,7 do
  local a=k/8+sp
  line(x,y,x+cos(a)*r*1.5,y+sin(a)*r*1.5,8)
 end
 circfill(x,y,r*0.8,8)
 circfill(x,y,r*0.45,2)
 if r>3 then pset(x-r*0.25,y-r*0.25,14) end
end

function draw_ship()
 local s=f/zp
 local bx=64+cos(pa)*pr*s    -- ship center on the rim
 local by=64+sin(pa)*pr*s
 local nx,ny=cos(pa+0.5),sin(pa+0.5)   -- nose dir (toward center)
 local sx,sy=cos(pa+0.75),sin(pa+0.75) -- sideways dir
 -- local->screen: +ly = toward nose (inward), lx = sideways
 local function rp(lx,ly) return bx+lx*sx-ly*nx, by+lx*sy-ly*ny end
 local function tri(ax,ay,b1,b2,c1,c2,col)
  local x1,y1=rp(ax,ay) local x2,y2=rp(b1,b2) local x3,y3=rp(c1,c2)
  trifill(x1,y1,x2,y2,x3,y3,col)
 end
 local function fc(lx,ly,r,col) local x,y=rp(lx,ly) circfill(x,y,r,col) end
 local function dt(lx,ly,col) local x,y=rp(lx,ly) pset(x,y,col) end
 local fl=rnd(1.5)
 -- swept wings (tips angle out)
 tri(-2,-2,-9,-5,-2,3,13)
 tri(2,-2,9,-5,2,3,13)
 tri(-2,-1,-7,-3,-2,2,12)
 tri(2,-1,7,-3,2,2,12)
 dt(-9,-5,8) dt(9,-5,8)
 -- hull: nose points inward at the incoming stream
 tri(-4,4,4,4,0,-7,5)
 tri(-3,4,3,4,0,-5,6)
 fc(0,-3,1.3,12) dt(0,-4,7)
 -- twin engines firing outward toward the rim
 fc(-2,4,1.6,5) fc(2,4,1.6,5)
 fc(-2,4+fl*0.4,1.3,9) fc(2,4+fl*0.4,1.3,9)
 fc(-2,4,0.8,10) fc(2,4,0.8,10)
 dt(-2,4,7) dt(2,4,7)
 fc(0,6+fl,1.3,12) dt(0,7+fl,7)
end

function trifill(x1,y1,x2,y2,x3,y3,col)
 if y1>y2 then x1,y1,x2,y2=x2,y2,x1,y1 end
 if y1>y3 then x1,y1,x3,y3=x3,y3,x1,y1 end
 if y2>y3 then x2,y2,x3,y3=x3,y3,x2,y2 end
 for y=flr(y1),flr(y3) do
  local xa=edge(y1,y3,x1,x3,y)
  local xb
  if y<y2 then xb=edge(y1,y2,x1,x2,y)
  else xb=edge(y2,y3,x2,x3,y) end
  rectfill(xa,y,xb,y,col)
 end
end

function edge(ya,yb,xa,xb,y)
 if yb==ya then return xb end
 local t=mid(0,(y-ya)/(yb-ya),1)   -- clamp, no extrapolation
 return xa+(xb-xa)*t
end

-->8
-- ui

function draw_hud()
 print("score "..score,3,3,7)
 print("best "..best,3,10,5)
 if inv then print("inv",52,3,t%16<8 and 11 or 3) end
 for i=1,lives do
  local x=124-(i-1)*9
  trifill(x,7,x-3,12,x+3,12,12)
  pset(x,9,7)
 end
 -- energy cell
 print("nrg",3,18,6)
 rect(19,18,60,23,5)
 local ew=(inv and 1 or energy/100)*40
 if ew>0 then rectfill(20,19,20+ew,22,(inv or energy>20) and 11 or 8) end
 -- shrink warning
 if rt<minrt+0.6 and t%30<15 then
  print("tunnel critical!",34,108,8)
 end
 if inboss then
  -- guardian integrity
  print("guardian",2,119,8)
  rectfill(0,126,127,127,1)
  local hw2=flr(boss.hp/boss.maxhp*128)
  if hw2>0 then rectfill(0,126,hw2,127,8) end
 else
  -- descent progress to the guild gate
  print("sector "..zone,2,119,6)
  print("gate",109,119,depth>80 and 8 or 5)
  rectfill(0,126,127,127,1)
  local dw=flr(depth/100*128)
  if dw>0 then rectfill(0,126,dw,127,depth>80 and (t%8<4 and 8 or 10) or 12) end
 end
end

function brieftext()
 local b={
  {"the guild barely","holds the outer","conduit. break","through & grab","every crystal."},
  {"the toll relay","bleeds traders","dry. kill it &","tariffs fall.","mind the rocks."},
  {"cargo spur next.","they haul stolen","energy here.","drones run thick","- stay sharp."},
  {"reactor spine.","this powers","their fleet.","heavy guard, but","worth the hit."},
  {"the core vault.","heart of their","greed. end it.","...but watch the","collapse, rebel."},
 }
 return b[levidx or min(zone,#b)]
end

function draw_bossdead()
 local p=1-deadtmr/80
 for i=0,2 do
  local r=p*72-i*14
  if r>0 and r<120 then circ(64,64,r,({7,10,8})[i+1]) end
 end
 local fr=(1-p)*22
 if fr>0 then circfill(64,64,fr,7) circfill(64,64,fr*0.6,10) end
 for i=1,10 do
  local d=p*64
  pset(64+cos(i/10)*d,64+sin(i/10)*d,({7,10,9,8})[i%4+1])
 end
 if deadtmr>40 then cprint("core destroyed",70,7) end
end

function draw_victory()
 rectfill(7,11,120,118,0)
 rect(6,10,121,119,11)
 -- jax sign-off portrait
 palt(0,false) sspr(0,0,48,48,10,18) palt()
 rect(9,17,59,67,11)
 print("the guild falls",62,20,11)
 local ep={"the heart is","ash. the guild","is broken. the","tunnels are","ours... for now.","- cmdr jax"}
 for i=1,#ep do print(ep[i],62,30+(i-1)*7,7) end
 line(10,74,117,74,5)
 print("score "..score,12,80,10)
 print("best "..best,74,80,6)
 print("new game +"..(ngplus+1),12,90,9)
 if t%30<20 then cprint("press z/x to continue",106,7) end
end

function draw_brief()
 rectfill(2,16,125,108,0)
 rect(2,16,125,108,12)
 print("incoming // cmdr jax",6,20,12)
 -- portrait
 palt(0,false)
 sspr(0,0,48,48,6,28)
 palt()
 rect(5,27,54,76,5)
 -- briefing
 local b=brieftext()
 for i=1,#b do print(b[i],58,30+(i-1)*9,7) end
 print("sector "..zone.."  "..zonename(),6,82,10)
 if ngplus>0 then print("new game +"..ngplus.."  (endless)",6,90,9) end
 if t%30<20 then cprint("press z/x to deploy",99,6) end
end

function draw_debrief()
 if not debrief_cap then
  memcpy(0x8000,0x6000,0x2000)   -- stash the frozen gameplay frame
  debrief_cap=true
 else
  memcpy(0x6000,0x8000,0x2000)   -- redraw it behind the popup
 end
 -- dim the frozen scene so the popup reads
 fillp(0b0101101001011010)
 rectfill(0,0,127,127,0)
 fillp()
 -- popup card
 rectfill(14,28,113,96,0)
 rect(14,28,113,96,11)
 cprint(zonename(),34,9)
 cprint("sector cleared",44,11)
 line(26,54,101,54,5)
 print("enemies blasted",22,60,7) print(kills,98,60,10)
 print("crystals taken",22,70,7) print(gemct,98,70,10)
 print("boss bonus",22,80,7) print("+500",98,80,10)
 if t%30<20 then cprint("press z/x",88,6) end
end

-- unwrapped side view: x=angle, vertical=depth z. shows each threat's
-- full z-column, the ship plane, and when the code calls it dangerous.
function draw_debug()
 local sy0,sy1=88,126
 local zmax,zmin=70,-5
 local function yz(z) return sy0+(zmax-z)/(zmax-zmin)*(sy1-sy0) end
 rectfill(0,sy0,127,sy1,0)
 rect(0,sy0,127,sy1,5)
 line(0,yz(zp),127,yz(zp),11) print("zp",1,yz(zp)-5,11)   -- ship plane
 line(0,yz(7),127,yz(7),9)    print("edge",1,yz(7)-5,9)   -- ~screen edge
 line(0,yz(1),127,yz(1),8)    print("dead",1,yz(1)-5,8)   -- removed at z<=1
 local sx=(pa%1)*127
 line(sx,sy0+1,sx,sy1,6)
 rectfill(sx-1,yz(zp)-1,sx+1,yz(zp)+1,7)                  -- ship
 for o in all(objs) do
  if o.kind=="wall" or o.kind=="fire" or o.kind=="rail" then
   local ox=(o.ang%1)*127
   local zl=o.zlen or 1
   local w=max(1,o.hw*127)
   local yt=mid(sy0+1,yz(o.z+zl),sy1)
   local yb=mid(sy0+1,yz(o.z),sy1)
   local dang
   if o.kind=="fire" then dang=(o.z<=zp and o.z>zp-2)
   else dang=(not o.hit) and o.z<=zp and o.z+zl>1 end
   rectfill(ox-w,yt,ox+w,yb, o.hit and 13 or (dang and 8 or 3))
  end
 end
 print("dbg",1,sy0+1,6)
end

function draw_title()
 local s=t%60<40
 rect(30,39,98,69,12)
 rectfill(31,40,97,68,0)
 print("tunnel runner",38,44,12)
 print("dodge \f8mines",42,53,7)
 print("grab \fcgems",46,61,7)
 if s then print("press \faz\f7 or \fax\f7 to fly",26,86,7) end
 print("\f6left/right orbit",30,100,6)
 print("\fcgems\f6 power \faz/x\f6 fire",24,108,6)
end

function draw_over()
 rectfill(28,42,100,90,0)
 rect(28,42,100,90,8)
 print("game over",47,48,8)
 print("score "..score,46,60,7)
 print("best  "..best,46,68,10)
 if score>=best and score>0 then print("new best!",47,76,11) end
 if t>30 and t%30<20 then print("\faz/x\f7 = retry",42,84,7) end
end

function cprint(s,y,c)
 print(s,64-#s*2,y,c)
end

function draw_banner()
 rectfill(0,52,127,72,0)
 line(0,52,127,52,12) line(0,72,127,72,12)
 cprint("sector "..zone,56,7)
 cprint(zonename(),64,12)
end

function draw_warning()
 if t%20<12 then cprint("guardian ahead",70,8) end
end

function draw_gate()
 rectfill(0,46,127,82,0)
 rect(0,46,127,82,8)
 cprint("guild gate",54,10)
 if gatetimer%20<12 then cprint("guardian detected",64,8) end
 cprint("breaching...",73,7)
end
__gfx__
00000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000011100010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000011111011000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000001111111100111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000011111111111001110110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000111111111100110011000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000011511111110001111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000001115511111110000111111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000011155111511100110111100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000001111111115511111111151110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000011111111155511111111551111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000001111111511111011111100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000011111111111010011111110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000111101110111001110111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000001110011001100ff100110d61000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000011000010011004fff0100d611100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000001100001104400eff4001006111100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000001004404ff01111001111100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000101014f2000001001111100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000100ff270074001111100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000001114fff764ff011111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000ffffffffff0610000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000ff4ffffff06d00011000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000004fffffeff01010000810000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000ff44f4fff1000011110000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000fffffff00011111100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000110ffff0001111111100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000811000ff08811111111100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000181000000008111a11111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000011000000010111aaa11100dd000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000010000000101111a11100666660000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000001000000101111111006666661000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000111100011001111111066666d10000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000066101001000011111101d6665011000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000665101011110111111101ddd50111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000055010101111011111010005501111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000100000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000001000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000111100000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000011000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000011111111111111111111000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000001111111100000011000000111111110000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000001111100000000000011000000000000111110000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000001111100000000000000011000000000000000111110000000000000000000000000000000000000000000
00000000000000000000000000000000000000000111100000000000000000011000000000000000000111100000000000000000000000000000000000000000
00000000000000000000000000000000000110011100000000000000000000011000000000000000000000111001100000000000000000000000000000000000
00000000000000000000000000000000001111110000000000000000000000011000000000000000000000001111110000000000000000000000000000000000
00000000000000000000000000000000001111000000000000000000000000011000000000000000000000000011110000000000000000000000000000000000
00000000000000000000000000000000001111000000000000000000000000011000000000000000000000000011110000000000000000000000000000000000
00000000000000000000000000000000111011100000000000000000000000011000000000000000000000000111011100000000000000000000000000000000
00000000000000000000000000000001100011100000000000000000000000011000000000000000000000000111000110000000000000000000000000000000
00000000000000000000000000000111000001110000000000000001111111111111111110000000000000001110000011100000000000000000000000000000
00000000000000000000000000001100000001110000000000011111100000011000000111111000000000001110000000110000000000000000000000000000
00000000000000000000000000011000000000111000000011111000000000011000000000011111000000011100000000011000000000000000000000000000
00000000000000000000000000110000000000011000001110000000000000011000000000000001110000011000000000001100000000000000000000000000
00000000000000000000000001100000000000011101111000000000000000011000000000000000011110111000000000000110000000000000000000000000
00000000000000000000000011000000000000001111100000000000000000011000000000000000000111110000000000000011000000000000000000000000
00000000000000000000000110000000000000001110000000000000000000011000000000000000000001110000000000000001100000000000000000000000
00000000000000000000001100000000000000111111000000000000000000011000000000000000000011111100000000000000110000000000000000000000
00000000000000000000011000000000000001100011000000000000000000011000000000000000000011000110000000000000011000000000000000000000
00000000000000000000110000000000000011000011100000000000000000011000000000000000000111000011000000000000001100000000000000000000
00000000000000000001100000000000001110000001100000000000000000011000000000000000000110000001110000000000000110000000000000000000
00000000000000000001000000000000011000000001110000000000dddddddddddddddd00000000001110000000011000000000000010000000000000000000
00000000000000000011000000000000110000000000110000000ddddd000001100000ddddd00000001100000000001100000000000011000000000000000000
00000000000000000110000000000001100000000000011000dddd00000000011000000000dddd00011000000000000110000000000001100000000000000000
000000000000000001000000000000110000000000000110ddd00000000000011000000000000ddd011000000000000011000000000000100000000000000000
0000000000000011110000000000011000000000000000ddd000000000000001100000000000000ddd0000000000000001100000000000111100000000000000
000000000000011110000000000001000000000000000dd1100000000000000110000000000000011dd000000000000000100000000000011110000000000000
0000000000000111111000000000110000000000000ddd011000000000000001100000000000000110ddd0000000000000110000000001111110000000000000
000000000000001111111000000110000000000000dd0000110000000000000110000000000000110000dd000000000000011000000111111100000000000000
00000000000000100111110000110000000000000dd000001100000000000001100000000000001100000dd00000000000001100001111100100000000000000
0000000000000110000111110010000000000000dd00000001100000000000011000000000000110000000dd0000000000000100111110000110000000000000
000000000000010000000111111000000000000dd0000000001000000000000110000000000001000000000dd000000000000111111000000010000000000000
00000000000011000000000111100000000000dd000000000011000000cccccccccccc000000110000000000dd00000000000111100000000011000000000000
0000000000001000000000001111100000000dd0000000000001000cccc0000110000cccc0001000000000000dd0000000011111000000000001000000000000
000000000001100000000001101111100000dd000000000000011ccc0000000110000000ccc110000000000000dd000001111101100000000001100000000000
000000000001100000000001100011110000d00000000000000ccc00000000011000000000ccc00000000000000d000011110001100000000001100000000000
00000000000100000000000100000011110dd0000000000000cc010000000000000000000010cc0000000000000dd01111000000100000000000100000000000
0000000000110000000000110000000011dd000000000000ccc00100000000000000000000100ccc000000800000dd1100000000110000000000110000000000
0000000000110000000000100000000000d110000000000cc000001000000000000000000100000cc000088800011d0000000000010000000000110000000000
000000000010000000000110000000000dd11110000000cc00000001000000000000000010000000cc00882881111dd000000000011000000000010000000000
000000000110000000000100000000000d0001110000c0c0000000010000000000000000100000000c000888111000d000000000001000000000011000000000
00000000011000000000010000000000dd000001110cccc0000000001000000000000001000000000cc00081100000dd00000000001000000000011000000000
00000000010000000000110000000000d000000001ccccc00000000010000000000000010000000000cc11100000000d00000000001100000000001000000000
00000000010000000000110000000000d00000000ccc7ccc00000000010cccccccccc01000000000000c10000000000d00000000001100000000001000000000
0000000001000000000010000000000dd000000000ccccc0000000000cccc000000cccc000000000011cc0000000000dd0000000000100000000001000000000
0000000011000000000010000000000d00000000000ccc0100000000cc100000000001cc000000001000c00000000000d0000000000100000000001100000000
0000000011000000000110000000000d0000000000ccc0001100000cc00000000000000cc00000110000cc0000000000d0000000000110000000001100000000
000000001100000000011000000000dd0000000000c00000001100cc0001000000001000cc00110000000c0000000000dd000000000110000000001100000000
000000001000000000010000000000dd0000000000c0000000001cc000000000000000000cc1000000000c0000000000dd000000000010000000000100000000
000000001000000000010000000000d0000000000cc0000000000c10000000cccc00000001c0000000000cc0000000000d000000000010000000000100000000
000000001000000000010000000000d0000000000c0000000000cc001000cccccccc000100cc0000000000c0000000000d000000000010000000000100000000
000000001000000000010000000000d0000000000c0000000000cc00000cccccccccc00000cc0000000000c0000000000d000000000010000000000100000000
000000001000000000010000000000d0000000000c0000000000c000000ccc7777ccc000000c0000000000c0000000000d000000000010000000000100000000
000000101000000000010000000000d0000000000c0000000000c00000ccc777777ccc00000c0000000000c0000000000d000000000010000000000101000000
000000111111111111111111111111d1111111111c1110000000c00000ccc777777ccc00000c0000000111c1111111111d111111111111111111111111000000
000000111111111111111111111111d1111111111c1110000000c00000ccc777777ccc00000c0000000111c1111111111d111111111111111111111111000000
000000101000000000010000000000d0000000000c0000000000c00000ccc777777ccc00000c0000000000c0000000000d000000000010000000000101000000
000000001000000000010000000000d0000000000c0000000000c000000ccc7777ccc000000c0000000000c0000000000d000000000010000000000100000000
000000001000000000010000000000d0000000000c0000000000cc00000cccccccccc00000cc0000000000c0000000000d000000000010000000000100000000
000000001000000000010000000000d0000000000c0000000000cc001000cccccccc000100cc0000000000c0000000000d000000000010000000000100000000
000000001000000000010000000000d0000000000cc0000000000c10000000cccc00000001c0000000000cc0000000000d000000000010000000000100000000
000000001000000000010000000000dd0000000000c0000000001cc000000000000000000cc1000000000c0000000000dd000000000010000000000100000000
000000001100000000011000000000dd0000000000c00000001100cc0001000000001000cc00110000000c0000000000dd000000000110000000001100000000
0000000011000000000110000000000d0000000000cc00001100000cc00000000000000cc00000110000cc0000000000d0000000000110000000001100000000
0000000011000000000010000000000d00000000000c000100000000cc100000000001cc000000001000c00000000000d0000000000100000000001100000000
0000000001000000000010000000000dd0000000000cc110000000000cccc000000cccc000000000011cc0000000000dd0000000000100000000001000000000
00000000010000000000110000000000d00000000001c00000000000010cccccccccc01000000000000c10000000000d00000000001100000000001000000000
00000000010000000000110000000000d00000000111cc000000000010000000000000010000000000cc11100000000d00000000001100000000001000000000
00000000011000000000010000000000dd00000111000cc0000000001000000000000001000000000cc00011100000dd00000000001000000000011000000000
000000000110000000000100000000000d000111000000c0000000010000000000000000100000000c000000111000d000000000001000000000011000000000
000000000010000000000110000000000dd11110000000cc00000001000000000000000010000000cc00000001111dd000000000011000000000010000000000
0000000000110000000000100000000000d110000000000cc000001000000000000000000100000cc000000000011d0000000000010000000000110000000000
0000000000110000000000110000000011dd000000000000ccc00100000000000000000000100ccc000000000000dd1100000000110000000000110000000000
00000000000100000000000100000011110dd0000000000000cc010000000000000000000010cc0000000000000dd01111000000100000000000100000000000
000000000001100000000001100011110000d00000000000000ccc00000000011000000000ccc00000000000000d000011110001100000000001100000000000
000000000001100000000001101111100000dd000000000000011ccc0000000110000000ccc110000000000000dd000001111101100000000001100000000000
0000000000001000000000001111100000000dd0000000000001000cccc0000110000cccc0001000000000000dd0000000011111000000000001000000000000
00000000000011000000000111100000000000dd000000000011000000cccccccccccc000000110000000000dd00000000000111100000000011000000000000
000000000000010000000111111000000000000dd0000000001000000000000110000000000001000000000dd000000000000111111000000010000000000000
0000000000000110000111110010000000000000dd00000001100000000000011000000000000110000000dd0000000000000100111110000110000000000000
00000000000000100111110000110000000000000dd000001100000000000001100000000000001100000dd00000000000001100001111100100000000000000
000000000000001111111000000110000000000000dd0000110000000000000110000000000000110000dd000000000000011000000111111100000000000000
0000000000000111111000000000110000000000000ddd011000000000000001100000000000000110ddd0000000000000110000000001111110000000000000
000000000000011110000000000001000000000000000dd1100000000000000110000000000000011dd000000000000000100000000000011110000000000000
0000000000000011110000000000011000000000000000ddd000000000000001100000000000000ddd0000000000000001100000000000111100000000000000
000000000000000001000000000000110000000000000110ddd00000000000011000000000000ddd011000000000000011000000000000100000000000000000
00000000000000000110000000000001100000000000011000dddd00000000011000000000dddd00011000000000000110000000000001100000000000000000
00000000000000000011000000000000110000000000110000000ddddd000001100000ddddd00000001100000000001100000000000011000000000000000000
00000000000000000001000000000000011000000001110000000000dddddddddddddddd00000000001110000000011000000000000010000000000000000000
00000000000000000001100000000000001110000001100000000000000000011000000000000000000110000001110000000000000110000000000000000000
00000000000000000000110000000000000011000011100000000000000000017000000000000000000111000011000000000000001100000000000000000000
0000000000000000000001100000000000000110001100000000000000000001c000000000000000000011000110000000000000011000000000000000000000
000000000000000000000011000000000000001111110000000000000000000ccc00000000000000000011111100000000000000110000000000000000000000
00000000000000000000000110000000000000001110000000000000000000ccccc0000000000000000001110000000000000001100000000000000000000000
0000000000000000000000001100000000000000111110000000000000000ccccccc000000000000000111110000000000000011000000000000000000000000
000000000000000000000000011000000000000111011110000000000000cccc7cccc00000000000011110111000000000000110000000000000000000000000
0000000000000000000000000011000000000001100000111000000000000ccccccc000000000001110000011000000000001100000000000000000000000000
00000000000000000000000000011000000000111000000011111000000000ccccc0000000011111000000011100000000011000000000000000000000000000
000000000000000000000000000011000000011100000000000111111cccc00ccc00cccc11111000000000001110000000110000000000000000000000000000
0000000000000000000000000000011100000111000000000000000111111111c111111110000000000000001110000011100000000000000000000000000000
00000000000000000000000000000001100011100000000000000000000000019000000000000000000000000111000110000000000000000000000000000000
0000000000000000000000000000000011101110000000000000000000000001a000000000000000000000000111011100000000000000000000000000000000
00000000000000000000000000000000001111000000000000000000000000011000000000000000000000000011110000000000000000000000000000000000
00000000000000000000000000000000001111000000000000000000000000011000000000000000000000000011110000000000000000000000000000000000
00000000000000000000000000000000001111110000000000000000000000011000000000000000000000001111110000000000000000000000000000000000
00000000000000000000000000000000000110011100000000000000000000011000000000000000000000111001100000000000000000000000000000000000
00000000000000000000000000000000000000000111100000000000000000011000000000000000000111100000000000000000000000000000000000000000
00000000000000000000000000000000000000000001111100000000000000011000000000000000111110000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000001111100000000000011000000000000111110000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000001111111100000011000000111111110000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000011111111111111111111000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000011000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000111100000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
00060000244502b450304650000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0004000014673106730c6650865505645000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000a0000213501c35018350133500e355000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000600001f550265502b5660000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000c00000c1300c130131300c1300f1300c130111300c1300c1300c130131300c1301413013130111300f1300c1300c130131300c1300f1300c130111300c1300c13011130131301413016130181301613013130
000c000024720287202b720307202b72028720247201f72024720287202b7203072033720307202b7202872024720287202b720307202b72028720247201f7201f72024720287202b72030720337203772030720
000300002d75322745186350000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
00 04054041

