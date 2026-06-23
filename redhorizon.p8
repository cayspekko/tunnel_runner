pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- red horizon
-- by claude + you
--
-- real-time mars artillery duel.
-- a soldier runs between 4 blocks;
-- a separate tank fights the duel.
--
--   mine -> dig raw regolith
--   refn -> raw into ONE of:
--           fuel / energy / shells
--   move -> spend fuel to relocate
--           the tank (dodge!)
--   gun  -> aim (free) + fire (shell)
--
-- screen, top to bottom:
--   offense : your blind fire at the
--             hidden enemy (short/long)
--   defense : your tank + where enemy
--             shells land. creeping in?
--             run to MOVE and dodge.
--   outpost : the soldier + 4 blocks
--
-- energy(en) = shields (damage buffer)

-->8
-- config / tunables

rangemax=20      -- battle line length
yhpmax=12
ehpmax=12
rawcap=12
rescap=12
digrate=3.2      -- raw per second
refrate=2.4      -- conversions per second
movecost=1       -- fuel per tank step
firecost=1       -- shells per shot
firecd=0.35      -- seconds between shots
shelldur=0.45    -- player shell flight
ewarn=1.40       -- enemy shell telegraph
dmg_direct=3
dmg_near=1

-- four station blocks (the soldier
-- walks between these)
stations={
 {x=16, name="mine"},
 {x=48, name="refn"},
 {x=80, name="move"},
 {x=112,name="gun"},
}
station_r=13

-- vertical layout
off_horizon=38   -- offense ground line
off_ruler=41     -- offense range ruler
def_ground=70    -- your tank's ground
out_surf=80      -- outpost surface
block_y=84       -- station blocks

-- campaign: named foes, pure numbers.
-- cad=base fire interval, ramp=how
-- fast it tightens over a match,
-- step=homing sharpness, relo=base
-- reposition interval, esh=shield
-- (eats your near-misses), salvo=
-- bracketing 2-shell volley.
levels={
 {name="dozer", cad=4.2,ramp=0.008,step=1,relo=11,esh=0,salvo=false},
 {name="scout", cad=3.6,ramp=0.014,step=1,relo=8, esh=0,salvo=false},
 {name="ranger",cad=3.1,ramp=0.018,step=2,relo=5, esh=0,salvo=false},
 {name="warden",cad=2.8,ramp=0.020,step=2,relo=5, esh=2,salvo=false},
 {name="reaper",cad=2.3,ramp=0.026,step=2,relo=4, esh=3,salvo=true},
}
mincad=1.2       -- fastest enemy cadence
eshregen=4.0     -- secs per enemy shield regen

-->8
-- helpers

function clamp(v,lo,hi) return mid(lo,v,hi) end

-- battle-range (1..rangemax) -> screen x
function rx(r)
 return 8+(r-1)/(rangemax-1)*112
end

function bar(x,y,w,v,vmax,c)
 rectfill(x,y,x+w,y+4,1)
 local fw=flr(w*clamp(v/vmax,0,1))
 if fw>0 then rectfill(x,y,x+fw,y+4,c) end
 rect(x,y,x+w,y+4,5)
end

function ptext(s,x,y,c,oc)
 print(s,x+1,y+1,oc or 0)
 print(s,x,y,c)
end
function ctext(s,y,c,oc)
 ptext(s,64-#s*2,y,c,oc)
end
function shake(n) shk=max(shk or 0,n) end

-->8
-- state

function _init()
 poke(0x5f2c,0)
 state="title"
 t=0 shk=0 best=0
 dust={}
 curlevel=1 totalscore=0
 setup_level()
end

function start_campaign()
 curlevel=1 totalscore=0
 setup_level()
end

-- set up a fresh match against the
-- current level's foe.
function setup_level()
 lvl=levels[curlevel]
 -- player
 yhp=yhpmax
 raw=0 fuel=4 energy=4 shells=3
 outmode=3 -- 1 fuel 2 energy 3 shells
 sol_x=stations[2].x   -- soldier (selector)
 sol_face=1
 ypos=flr(rangemax/2) -- your tank position
 aim=flr(rangemax/2)  -- your gun aim
 fire_cd=0 refbuf=0
 -- enemy
 ehp=ehpmax
 epos=2+flr(rnd(rangemax-3))
 eaim=1+flr(rnd(rangemax))
 etimer=3.2
 erelo=lvl.relo
 eshield=lvl.esh
 eshtimer=eshregen
 -- shots
 myshot=nil   -- {r,tt,dur}
 enshot=nil   -- {tt,dur,aims={..}}
 mymark=nil   -- last offense impact {x,life,c}
 ecraters={}  -- enemy impacts on your line
 -- feedback
 verdict="" vtime=0 vcol=7
 cue="" ctime=0 ccol=7
 introt=2.2   -- level intro banner
 -- score
 shots_fired=0 hits=0 gtime=0
 dust={}
end

function set_verdict(s,c) verdict=s vtime=1.5 vcol=c end
function set_cue(s,c) cue=s ctime=1.2 ccol=c end

-->8
-- update

function _update60()
 t+=1/60
 if shk>0 then shk=max(0,shk-0.6) end
 upd_dust(1/60)
 if state=="title" then
  if btnp(4) or btnp(5) then start_campaign() state="play" sfx(6) end
 elseif state=="play" then upd_play()
 elseif state=="levelclear" then
  if btnp(4) or btnp(5) then curlevel+=1 setup_level() state="play" sfx(6) end
 else -- win / lose
  if btnp(4) or btnp(5) then state="title" sfx(6) end
 end
end

function cur_station()
 for i=1,#stations do
  if abs(sol_x-stations[i].x)<station_r then return i end
 end
 return nil
end

function upd_play()
 local dt=1/60
 gtime+=dt
 if fire_cd>0 then fire_cd-=dt end
 if vtime>0 then vtime-=dt end
 if ctime>0 then ctime-=dt end

 if introt>0 then introt-=dt end
 -- enemy cadence tightens as match drags
 local ecad=max(mincad,lvl.cad-gtime*lvl.ramp)
 -- enemy shields slowly regenerate
 if lvl.esh>0 and eshield<lvl.esh then
  eshtimer-=dt
  if eshtimer<=0 then eshield+=1 eshtimer=eshregen end
 end

 -- soldier walks (free, costs only time)
 sol_moving=false
 if btn(0) then sol_x-=1.4 sol_face=-1 sol_moving=true end
 if btn(1) then sol_x+=1.4 sol_face=1 sol_moving=true end
 sol_x=clamp(sol_x,8,120)

 local si=cur_station()

 if si==1 then -- MINE
  if btn(4) and raw<rawcap then
   raw=min(rawcap,raw+digrate*dt)
   if t%0.18<dt then sfx(0) end
   if rnd()<0.5 then add_dust(stations[1].x+rnd(8)-4,out_surf+24,2) end
  end

 elseif si==2 then -- REFN
  if btnp(3) then outmode=outmode%3+1 sfx(6) end       -- down: next
  if btnp(2) then outmode=(outmode-2)%3+1 sfx(6) end   -- up: prev
  if btn(4) and raw>=1 then
   refbuf+=refrate*dt
   if t%0.2<dt then sfx(1) end
   while refbuf>=1 and raw>=1 do
    refbuf-=1 raw-=1
    if outmode==1 then fuel=min(rescap,fuel+1)
    elseif outmode==2 then energy=min(rescap,energy+1)
    else shells=min(rescap,shells+1) end
   end
  end

 elseif si==3 then -- MOVE (relocate tank)
  if btnp(2) or btnp(3) then
   if fuel>=movecost then
    fuel-=movecost
    ypos=clamp(ypos+(btnp(2) and 1 or -1),1,rangemax)
    sfx(4) shake(1)
    add_dust(rx(ypos),def_ground,5)
   else
    set_cue("no fuel!",8)
   end
  end

 elseif si==4 then -- GUN
  if btnp(2) then aim=clamp(aim+1,1,rangemax) sfx(6) end
  if btnp(3) then aim=clamp(aim-1,1,rangemax) sfx(6) end
  if btnp(4) and fire_cd<=0 and shells>=firecost and not myshot then
   shells-=firecost fire_cd=firecd shots_fired+=1
   sfx(2)
   myshot={r=aim,tt=0,dur=shelldur}
  end
 end

 -- my shot in flight
 if myshot then
  myshot.tt+=dt
  if myshot.tt>=myshot.dur then
   resolve_my_shot() myshot=nil
  end
 end

 -- enemy launch / flight
 if not enshot then
  etimer-=dt
  if etimer<=0 then
   local aims
   if lvl.salvo then
    -- bracket: straddle the lock so a
    -- single-step nudge won't save you
    aims={clamp(eaim-1,1,rangemax),clamp(eaim+1,1,rangemax)}
   else
    aims={eaim}
   end
   enshot={tt=0,dur=ewarn,aims=aims} sfx(5)
  end
 else
  enshot.tt+=dt
  if enshot.tt>=enshot.dur then
   resolve_enemy_shot(enshot.aims)
   enshot=nil etimer=ecad
  end
 end

 -- enemy repositions (your aim goes stale)
 erelo-=dt
 if erelo<=0 then
  erelo=lvl.relo+rnd(2)
  local old=epos
  repeat epos=2+flr(rnd(rangemax-3)) until abs(epos-old)>=3
  set_cue("enemy repositioned",10)
 end

 -- crater fade
 for c in all(ecraters) do
  c.life-=dt
  if c.life<=0 then del(ecraters,c) end
 end
 if mymark then
  mymark.life-=dt
  if mymark.life<=0 then mymark=nil end
 end

 if ehp<=0 then ehp=0 win()
 elseif yhp<=0 then yhp=0 lose() end
end

function resolve_my_shot()
 local d=abs(myshot.r-epos)
 local dealt,c=0,6
 if d==0 then
  dealt=dmg_direct c=8
  set_verdict("direct hit! -"..dealt,8) hits+=1 shake(4)
 elseif d==1 then
  local dir=myshot.r<epos and "short" or "long"
  if eshield>0 then
   eshield-=1 dealt=0 c=13
   set_verdict("absorbed!  ("..dir..")",13)
  else
   dealt=dmg_near c=10
   set_verdict("close -"..dealt.."  ("..dir..")",10) shake(2)
  end
 else
  local dir=myshot.r<epos and "short" or "long"
  set_verdict("miss  ("..dir..")",6)
 end
 mymark={x=rx(myshot.r),life=1.6,c=c}
 if dealt>0 then
  ehp=max(0,ehp-dealt) sfx(3)
  for i=1,6 do add_dust(rx(epos)+rnd(10)-5,off_horizon-rnd(8),8+flr(rnd(3))) end
 else
  sfx(7)
  add_dust(rx(myshot.r),off_horizon,5)
 end
end

-- enemy fires where it locked. if you
-- relocated since, ypos moved -> miss.
function resolve_enemy_shot(aims)
 local total=0
 for i=1,#aims do
  local a=aims[i]
  local d=abs(a-ypos)
  add(ecraters,{x=rx(a),life=2.2,hit=(d<=1)})
  if d==0 then total+=dmg_direct
  elseif d==1 then total+=dmg_near end
 end
 if total>0 then
  -- your shields (energy) absorb first
  local absorbed=min(energy,total)
  energy-=absorbed total-=absorbed
  if total>0 then yhp-=total shake(5) else shake(2) end
  sfx(3)
  for i=1,8 do add_dust(rx(ypos)+rnd(12)-6,def_ground-rnd(6),8+flr(rnd(3))) end
  if absorbed>0 and total==0 then set_cue("shields held!",12)
  else set_cue("tank hit!",8) end
 else
  sfx(7)
  set_cue("they missed!",11)
  add_dust(rx(aims[1]),def_ground,5)
 end
 -- enemy homes toward you by sharpness
 local s=lvl.step
 if eaim<ypos then eaim=min(ypos,eaim+s)
 elseif eaim>ypos then eaim=max(ypos,eaim-s) end
end

-- dust
function add_dust(x,y,c)
 add(dust,{x=x,y=y,dx=rnd(2)-1,dy=-rnd(1.5)-0.3,life=0.4+rnd(0.5),c=c})
end
function upd_dust(dt)
 for d in all(dust) do
  d.x+=d.dx d.y+=d.dy d.dy+=0.05 d.life-=dt
  if d.life<=0 then del(dust,d) end
 end
end

function win()
 local acc=shots_fired>0 and flr(hits/shots_fired*100) or 0
 score=flr(max(0,3000-gtime*10)+acc*15+yhp*40+energy*8)
 totalscore+=score
 sfx(8)
 if curlevel<#levels then
  state="levelclear"
 else
  best=max(best,totalscore)
  state="win"
 end
end
function lose() state="lose" sfx(9) end

-->8
-- draw

function _draw()
 cls(0)
 local ox,oy=0,0
 if shk>0 then ox=flr(rnd(shk)-shk/2) oy=flr(rnd(shk)-shk/2) end
 camera(ox,oy)
 if state=="title" then draw_title()
 else
  draw_offense()
  draw_defense()
  draw_outpost()
  draw_hud()
  if state=="play" and introt>0 then draw_intro() end
  if state=="levelclear" then draw_levelclear() end
  if state=="win" then draw_win() end
  if state=="lose" then draw_lose() end
 end
 camera()
end

function draw_intro()
 local s="lvl "..curlevel..": "..lvl.name
 local w=#s*4+8
 rectfill(64-w/2,30,64+w/2,42,0)
 rect(64-w/2,30,64+w/2,42,8)
 ctext(s,33,8)
end

function draw_title()
 for y=0,80 do rectfill(0,y,127,y, y<40 and 0 or (y<60 and 2 or 4)) end
 for i=0,3 do rectfill(0,70+i*5,127,127, i%2==0 and 4 or 9) end
 rectfill(6,60,16,70,2) rect(9,55,13,60,2)
 rectfill(108,60,120,70,2) rect(112,55,116,60,2)
 ctext("red horizon",20,8,2)
 ctext("a mars artillery duel",32,9)
 ctext("dig . refine . blind-fire",42,6)
 ctext("5 foes. destroy them all.",50,8)
 ctext("walk: \139\145   act: z",60,6)
 ctext("adjust block: up/down",66,6)
 ctext("mine refn move gun",74,12)
 if t%1<0.6 then ctext("press z to deploy",92,10,0) end
 if best>0 then ctext("best "..best,108,12) end
end

-- top zone: your blind fire at enemy
function draw_offense()
 rectfill(0,8,127,off_horizon,1)
 rectfill(0,16,127,off_horizon,2)
 -- enemy haze on the right
 for i=0,30 do
  local x=96+i
  if x<=127 then line(x,8,x,off_horizon, i<10 and 2 or (i<20 and 13 or 14)) end
 end
 ptext("\151enemy",100,9,14)
 rectfill(0,off_horizon-1,127,off_horizon,4)

 -- your gun (left), barrel by aim
 rectfill(1,off_horizon-5,9,off_horizon,5)
 local ang=0.30+(aim/rangemax)*0.16
 local bx,by=5,off_horizon-4
 line(bx,by,bx+cos(ang)*13,by-sin(ang)*13,6)
 line(bx,by-1,bx+cos(ang)*13,by-sin(ang)*13-1,7)

 -- range ruler + ticks
 line(8,off_ruler,120,off_ruler,5)
 for r=1,rangemax do
  local x=rx(r)
  line(x,off_ruler,x,off_ruler+((r%5==0) and 3 or 1),5)
 end
 -- last shot impact marker
 if mymark then
  rectfill(mymark.x-1,off_ruler-1,mymark.x+1,off_ruler+1,mymark.c)
 end
 -- aim reticle
 local ax=rx(aim)
 line(ax,off_ruler-1,ax,off_horizon-6,8)
 ptext("\148",ax-3,off_ruler+2,8)
 print(aim,ax-1,off_ruler+7,7)

 -- my shell arc
 if myshot then
  local p=myshot.tt/myshot.dur
  local sx=5+(rx(myshot.r)-5)*p
  local sy=off_horizon-4-sin(p*0.5)*30
  circfill(sx,sy,1,7) pset(sx,sy,10)
 end

 -- verdict
 if vtime>0 then ctext(verdict,10,vcol) end
end

-- middle zone: your tank + incoming
function draw_defense()
 rectfill(0,off_horizon+1,127,def_ground,0)
 rectfill(0,off_horizon+1,127,off_horizon+8,1)
 ptext("your tank",2,off_horizon+2,12)
 -- ground
 rectfill(0,def_ground,127,def_ground+3,4)
 line(0,def_ground,127,def_ground,9)

 -- enemy craters (where their shells hit)
 for c in all(ecraters) do
  local cc=c.hit and 8 or 5
  rectfill(c.x-2,def_ground-1,c.x+2,def_ground,cc)
  pset(c.x,def_ground-2,cc)
 end

 -- your tank at ypos
 local tx=rx(ypos)
 rectfill(tx-5,def_ground-4,tx+5,def_ground-1,11)
 rectfill(tx-3,def_ground-7,tx+2,def_ground-4,3)
 line(tx+2,def_ground-6,tx+8,def_ground-6,3) -- barrel
 for i=-4,4,2 do pset(tx+i,def_ground,0) end

 -- enemy incoming shell(s) + warning
 if enshot then
  local p=enshot.tt/enshot.dur
  for i=1,#enshot.aims do
   local lx=rx(enshot.aims[i])
   local sx=124+(lx-124)*p
   local sy=(off_horizon+2)+(def_ground-2-(off_horizon+2))*p-sin(p*0.5)*8
   circfill(sx,sy,1,8) pset(sx,sy,10)
   -- target shadow where it will land
   if t%0.2<0.1 then line(lx-3,def_ground+1,lx+3,def_ground+1,8) end
  end
  if t%0.5<0.3 then ptext("\135incoming\135",40,off_horizon+2,8) end
 end
end

-- bottom zone: soldier + 4 blocks
function draw_outpost()
 rectfill(0,out_surf-2,127,127,4)
 rectfill(0,out_surf-2,127,out_surf,9)
 rectfill(0,block_y+12,127,127,2)

 local si=cur_station()
 -- mine shaft
 rectfill(stations[1].x-4,block_y+8,stations[1].x+4,127,0)

 for i=1,#stations do
  local s=stations[i]
  local active=(si==i)
  local c=active and 10 or 6
  rectfill(s.x-8,block_y,s.x+8,block_y+9,active and 5 or 1)
  rect(s.x-8,block_y,s.x+8,block_y+9, active and 10 or 5)
  ptext(s.name,s.x-#s.name*2,block_y+2,c)
 end
 -- refinery output indicator
 local lbl={"fuel","enrgy","shell"}
 local lc={9,12,10}
 ptext("->"..lbl[outmode],stations[2].x-11,out_surf-9,lc[outmode])

 -- soldier (the selector)
 local fx=sol_x
 local step=(sol_moving and flr(t*10)%2==0) and 1 or 0
 -- head
 circfill(fx,out_surf-7,1,15)
 -- body
 line(fx,out_surf-6,fx,out_surf-2,12)
 -- arms
 line(fx-1,out_surf-5,fx+1,out_surf-5,12)
 -- legs
 line(fx,out_surf-2,fx-1-step,out_surf,4)
 line(fx,out_surf-2,fx+1+step,out_surf,4)

 -- dust particles
 for d in all(dust) do pset(d.x,d.y,d.c) end

 if ctime>0 then ctext(cue,out_surf-20,ccol) end
end

function draw_hud()
 ptext("you",1,0,11)
 bar(17,0,40,yhp,yhpmax,11)
 ptext("l"..curlevel,59,0,7)
 ptext("foe",126-12,0,8)
 bar(72,0,40,ehp,ehpmax,8)
 -- enemy shield pips
 if lvl.esh>0 then
  for i=1,lvl.esh do
   local px=72+(i-1)*5
   rectfill(px,6,px+3,7, i<=eshield and 12 or 1)
  end
 end

 local y=120
 ptext("raw",1,y,6) bar(16,y,20,raw,rawcap,4)
 ptext("fu",40,y,9)  bar(50,y,16,fuel,rescap,9)
 ptext("en",69,y,12) bar(79,y,16,energy,rescap,12)
 ptext("sh",98,y,10) bar(108,y,16,shells,rescap,10)
end

function draw_levelclear()
 rectfill(12,38,115,90,0) rect(12,38,115,90,11)
 ctext(lvl.name.." destroyed",44,11)
 local acc=shots_fired>0 and flr(hits/shots_fired*100) or 0
 ctext("score "..score.."  ("..acc.."%)",54,10)
 ctext("total "..totalscore,62,6)
 ctext("next foe: "..levels[curlevel+1].name,72,8)
 if t%1<0.6 then ctext("press z to advance",80,7) end
end
function draw_win()
 rectfill(10,36,117,92,0) rect(10,36,117,92,11)
 ctext("mars is yours",42,11)
 ctext("all 5 foes destroyed",52,10)
 ctext("final score "..totalscore,64,10)
 if totalscore>=best then ctext("new best!",74,14) end
 if t%1<0.6 then ctext("press z",84,7) end
end
function draw_lose()
 rectfill(14,46,113,82,0) rect(14,46,113,82,8)
 ctext("tank destroyed by "..lvl.name,52,8)
 ctext("reached lvl "..curlevel.."  held "..flr(gtime).."s",62,6)
 if t%1<0.6 then ctext("press z",72,7) end
end
__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00077000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00700700000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
000800000865005640046200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000a00001053012540145401653000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00040000222601c26016250102400a630066200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000300001467010660186600c65008640056300362000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000500000a34010350163501c34022330000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000b00001a53015530000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000800001e14000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000600000c63008620000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000a0000181501c1501f1502416000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000c000014250102500c2400824004630000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
