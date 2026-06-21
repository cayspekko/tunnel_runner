pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- tunnel runner
-- by claude + you

function _init()
 cx,cy=64,64
 f=90      -- focal length
 zp=12     -- ship plane depth
 best=0
 inv=false  -- invincibility cheat (pause-menu toggle)
 menuitem(1,"invincible: off",toggle_inv)
 music(0)  -- start bg loop
 reset_game()
 state="title"
end

function toggle_inv()
 inv=not inv
 menuitem(1,"invincible: "..(inv and "on" or "off"))
 return true  -- keep the pause menu open after toggling
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
 pops={}
 energy=40        -- weapon charge (from gems)
 firecd=0
 ringz={}
 for i=1,8 do ringz[i]=i*13 end
 rot=0
 shake=0
 spawn_t=20
 btimer=120
 dtimer=240
 zone=1
 zonelen=1400     -- frames of descent per zone
 depth=0          -- 0..100 progress to the gate
 zbanner=90
 gatetimer=0
 inboss=false
 boss=nil
 t=0
 flash=0
end

-->8
-- update

function _update60()
 t+=1
 if state=="title" then
  rot+=0.003
  move_rings(1.0)
  if btnp(4) or btnp(5) then
   sfx(3) reset_game() state="play"
  end
 elseif state=="play" then
  update_play()
 elseif state=="gate" then
  gatetimer-=1
  rot+=0.012
  move_rings(2.5)
  if gatetimer<=0 then start_boss() end
 elseif state=="over" then
  rot+=0.002
  move_rings(0.5)
  if t>30 and (btnp(4) or btnp(5)) then
   sfx(3) reset_game() state="play"
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
   objs={} bolts={}
   return
  end
 end
 -- survival score
 if t%6==0 then score+=1 end
 -- ship orbits the rim (left/right rotate, wraps full circle)
 local asp=0.014
 if btn(0) then pa-=asp end
 if btn(1) then pa+=asp end
 pa%=1
 pr=max(1.2,rt-0.9)        -- orbit radius tracks the shrinking rim
 -- tunnel slowly shrinks (held steady during a boss)
 if not inboss then rt=max(minrt,rt-0.0011) end
 rot+=0.004
 move_rings(1.2+d*0.12)
 -- spawning
 if inboss then
  update_boss(d)
 else
  spawn_t-=1
  if spawn_t<=0 then
   spawn_obj()
   spawn_t=max(10,26-d*3)
  end
  btimer-=1
  if btimer<=0 then
   spawn_wall()
   btimer=max(60,150-d*14)
  end
  dtimer-=1
  if dtimer<=0 then
   spawn_drone()
   dtimer=max(90,220-d*18)
  end
 end
 -- move objects
 local osp=1.0+d*0.18
 for o in all(objs) do
  local oz=o.z
  o.z-=osp
  if o.kind=="drone" then
   if o.flash>0 then o.flash-=1 end
   -- home toward the player's angle, locking harder as it nears
   local turn=0.003+(1-o.z/110)*0.006
   local dd=pa-o.ang
   if dd>0.5 then dd-=1 elseif dd<-0.5 then dd+=1 end
   o.ang+=mid(-turn,dd,turn)
  elseif o.kind=="fire" then
   o.ang=(o.ang+o.sweep)%1     -- sweeping barrier
  end
  if oz>zp and o.z<=zp then
   -- compare angle around the ring (shortest way, with wrap)
   local da=abs(o.ang-pa) da=min(da,1-da)
   if o.kind=="wall" or o.kind=="fire" then
    if da<o.hw then hit_mine() end   -- inside a barrier arc
   elseif o.kind=="gem" then
    local sr=pr*(f/zp)       -- rim radius in screen px
    if da<mid(0.05,11/(6.2832*sr),0.3) then collect(o) o.dead=true end
   else                      -- mine or drone
    local sr=pr*(f/zp)
    if da<mid(0.04,8/(6.2832*sr),0.25) then hit_mine() o.dead=true end
   end
  end
  if o.z<=1 then o.dead=true end
 end
 for o in all(objs) do
  if o.dead then del(objs,o) end
 end
 -- firing (gems = ammo): hold z/x
 firecd-=1
 if (btn(4) or btn(5)) and firecd<=0 and energy>=5 then
  add(bolts,{ang=pa,z=zp})
  energy-=5 firecd=7 sfx(6)
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
    elseif o.kind=="fire" then
     -- energy curtain: bolts pass through
    elseif da<0.05 and abs(b.z-o.z)<6 then
     b.dead=true
     local s=f/o.z
     local sx,sy=64+cos(o.ang)*pr*s,64+sin(o.ang)*pr*s
     if o.kind=="drone" then        -- armored: needs 3 hits
      o.hp-=1 o.flash=4 sfx(6)
      if o.hp<=0 then
       o.dead=true score+=40 sfx(1)
       add(pops,{x=sx,y=sy,life=22,txt="+40",col=10})
      end
     elseif o.kind=="gem" then      -- wasted a crystal
      o.dead=true
      add(pops,{x=sx,y=sy,life=18,txt="lost",col=5})
     else                          -- killed a mine
      o.dead=true score+=15 sfx(1)
      add(pops,{x=sx,y=sy,life=20,txt="+15",col=10})
     end
    end
   end
  end
  -- bolt reaches the guardian's rotating core
  if inboss and not b.dead and b.z>=boss.z then
   b.dead=true
   local cda=abs(b.ang-boss.coreang) cda=min(cda,1-cda)
   if cda<0.06 then
    boss.hp-=1 boss.flash=4 sfx(1)
    if boss.hp<=0 then win_boss() end
   end
  end
 end
 for b in all(bolts) do
  if b.dead then del(bolts,b) end
 end
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
 o.kind = rnd(1)<0.34 and "gem" or "mine"
 add(objs,o)
end

function next_zone()
 zone+=1
 depth=0
 zbanner=110
 rt=min(8,rt+1.2)        -- breathing room past the gate
 objs={} bolts={}
 inboss=false boss=nil
 spawn_t=30 btimer=120 dtimer=160
 state="play"
end

function start_boss()
 state="play"
 inboss=true
 objs={} bolts={}
 boss={hp=24,maxhp=24,coreang=0,corespin=0.0022,
       dtmr=50,ftmr=80,gtmr=60,flash=0,z=100}
end

function update_boss(d)
 local p2=boss.hp<=boss.maxhp/2          -- enraged phase
 boss.coreang=(boss.coreang+(p2 and 0.004 or boss.corespin))%1
 if boss.flash>0 then boss.flash-=1 end
 -- drone waves
 boss.dtmr-=1
 if boss.dtmr<=0 then
  spawn_drone()
  boss.dtmr=p2 and 50 or 90
 end
 -- sweeping fire curtains
 boss.ftmr-=1
 if boss.ftmr<=0 then
  spawn_fire(p2)
  boss.ftmr=p2 and 80 or 140
 end
 -- shed crystals so you can keep firing
 boss.gtmr-=1
 if boss.gtmr<=0 then
  local ang=rnd(1)
  add(objs,{kind="gem",ang=ang,x=cos(ang)*pr,y=sin(ang)*pr,
            z=110,r=0.7,spin=rnd(1)})
  boss.gtmr=110
 end
end

function spawn_fire(wide)
 local dir=rnd(1)<0.5 and 1 or -1
 add(objs,{kind="fire",ang=rnd(1),z=110,
           hw=wide and 0.16 or 0.10,
           sweep=dir*(wide and 0.006 or 0.004)})
end

function win_boss()
 score+=500
 flash=12 shake=16 sfx(1)
 add(pops,{x=64,y=64,life=40,txt="guardian down +500",col=11})
 inboss=false boss=nil
 next_zone()
end

function zonename()
 local n={"outer conduit","cargo spur","toll relay","reactor spine","core vault"}
 return n[min(zone,#n)]
end

function spawn_drone()
 add(objs,{kind="drone",ang=rnd(1),z=110,hp=3,flash=0,spin=rnd(1)})
end

function spawn_wall()
 local d=8-rt
 -- a mountain ridge spanning an arc of the wall
 local np=3+flr(rnd(3))      -- 3..5 peaks
 local hs={}
 for i=1,np do hs[i]=0.4+rnd(0.55) end
 add(objs,{
  kind="wall", ang=rnd(1),
  hw=0.055+rnd(0.05)+d*0.004, -- arc half-width (grows w/ difficulty)
  np=np, hs=hs, z=110,
 })
end

function collect(o)
 score+=25
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
 cls(0)
 local ox,oy=0,0
 if shake>0 then ox=rnd(4)-2 oy=rnd(4)-2 end
 camera(ox,oy)
 draw_tunnel()
 if state!="title" then
  if inboss then draw_boss() end
  draw_objs() draw_bolts() draw_ship()
 end
 camera()
 if flash>0 then
  for i=0,15 do pal(i,8) end
  rectfill(0,0,127,127,8) pal()
 end
 if state=="title" then
  draw_title()
 else
  draw_hud()
  if zbanner>0 then draw_banner() end
  if state=="play" and depth>80 then draw_warning() end
  if state=="gate" then draw_gate() end
  if state=="over" then draw_over() end
 end
end

function ring_col(z)
 if z>80 then return 1
 elseif z>50 then return 13
 elseif z>26 then return 12
 elseif z>13 then return 12
 else return 6 end
end

function draw_tunnel()
 -- vanishing-point glow
 circfill(cx,cy,2+sin(t/120),7)
 circ(cx,cy,4,12)
 -- rotating ribs
 for k=0,11 do
  local a=k/12+rot
  local c,s=cos(a),sin(a)
  local rn=rt*f/6
  local rf=rt*f/110
  line(cx+c*rn,cy+s*rn,cx+c*rf,cy+s*rf,1)
 end
 -- rings far->near
 for i=1,#ringz do
  local z=ringz[i]
  if z>2 then
   local r=rt*f/z
   if r<210 then circ(cx,cy,r,ring_col(z)) end
  end
 end
end

function draw_objs()
 -- array is near->far, draw far first
 for i=#objs,1,-1 do
  local o=objs[i]
  local z=o.z
  if z>1 then
   if o.kind=="wall" then
    draw_wall(o)
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
  line(ilx,ily,irx,iry,t%3==0 and 7 or 10)  -- hot inner edge
 end
end

function draw_boss()
 local x,y=64,64
 local hot=boss.flash>0
 local rr=30
 -- rotating armor spokes
 for k=0,5 do
  local a=k/6+t*0.003
  line(x,y,x+cos(a)*rr,y+sin(a)*rr,hot and 7 or 6)
 end
 circ(x,y,rr,5)
 circfill(x,y,rr-3,hot and 7 or 5)
 circfill(x,y,rr-7,1)
 -- rotating weak core (shoot this)
 local ca=boss.coreang
 local cx2=x+cos(ca)*(rr*0.5)
 local cy2=y+sin(ca)*(rr*0.5)
 local pul=2+sin(t/30)
 circfill(cx2,cy2,5+pul,8)
 circfill(cx2,cy2,3+pul,hot and 7 or 10)
 circfill(cx2,cy2,1+pul*0.5,7)
 -- central eye
 circfill(x,y,5,2)
 circfill(x,y,3,boss.hp<=boss.maxhp/2 and 8 or 9)
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

function draw_wall(o)
 local s=f/o.z
 local h=rt*0.55             -- max peak height (world units)
 local a1=o.ang-o.hw
 local stp=(o.hw*2)/o.np
 for i=1,o.np do
  local bl=a1+stp*(i-1)      -- base-left angle
  local br=a1+stp*i          -- base-right angle
  local am=(bl+br)*0.5       -- apex angle
  local hh=h*o.hs[i]
  -- base sits on the tunnel wall (radius rt), apex points inward
  local lx,ly=64+cos(bl)*rt*s,64+sin(bl)*rt*s
  local rx,ry=64+cos(br)*rt*s,64+sin(br)*rt*s
  local ax,ay=64+cos(am)*(rt-hh)*s,64+sin(am)*(rt-hh)*s
  trifill(lx,ly,rx,ry,ax,ay,4)   -- rock
  line(lx,ly,ax,ay,15)           -- sunlit edge
  line(rx,ry,ax,ay,2)            -- shadow edge
  if o.hs[i]>0.72 then           -- snow cap on tall peaks
   trifill(ax,ay,ax+(lx-ax)*0.32,ay+(ly-ay)*0.32,
                 ax+(rx-ax)*0.32,ay+(ry-ay)*0.32,7)
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
 local ew=(energy/100)*40
 if ew>0 then rectfill(20,19,20+ew,22,energy>20 and 11 or 8) end
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

