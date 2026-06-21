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
 music(0)  -- start bg loop
 reset_game()
 state="title"
end

function reset_game()
 pa=0           -- ship angle around the rim (0..1 turn)
 pr=7.1         -- ship orbit radius
 score=0
 lives=3
 rt=8.0         -- tunnel world radius
 minrt=2.6
 objs={}
 pops={}
 ringz={}
 for i=1,8 do ringz[i]=i*13 end
 rot=0
 shake=0
 spawn_t=20
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
 local d=(8-rt)            -- difficulty 0..5.4
 -- survival score
 if t%6==0 then score+=1 end
 -- ship orbits the rim (left/right rotate, wraps full circle)
 local asp=0.014
 if btn(0) then pa-=asp end
 if btn(1) then pa+=asp end
 pa%=1
 pr=max(1.2,rt-0.9)        -- orbit radius tracks the shrinking rim
 -- tunnel slowly shrinks
 rt=max(minrt,rt-0.0011)
 rot+=0.004
 move_rings(1.2+d*0.12)
 -- spawning
 spawn_t-=1
 if spawn_t<=0 then
  spawn_obj()
  spawn_t=max(10,26-d*3)
 end
 -- move objects
 local osp=1.0+d*0.18
 for o in all(objs) do
  local oz=o.z
  o.z-=osp
  if oz>zp and o.z<=zp then
   -- compare angle around the ring (shortest way, with wrap)
   local da=abs(o.ang-pa) da=min(da,1-da)
   local sr=pr*(f/zp)       -- rim radius in screen px
   if o.kind=="gem" then
    if da<mid(0.05,11/(6.2832*sr),0.3) then collect(o) o.dead=true end
   else
    if da<mid(0.04,8/(6.2832*sr),0.25) then hit_mine() o.dead=true end
   end
  end
  if o.z<=1 then o.dead=true end
 end
 for o in all(objs) do
  if o.dead then del(objs,o) end
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

function collect(o)
 score+=25
 rt=min(8,rt+0.06)       -- gems give breathing room
 sfx(0)
 local s=f/zp
 add(pops,{x=64+o.x*s,y=64+o.y*s,life=24,txt="+25"})
end

function hit_mine()
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
 if state!="title" then draw_objs() draw_ship() end
 camera()
 if flash>0 then
  for i=0,15 do pal(i,8) end
  rectfill(0,0,127,127,8) pal()
 end
 if state=="title" then draw_title()
 else draw_hud() end
 if state=="over" then draw_over() end
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
   local s=f/z
   local x,y=64+o.x*s,64+o.y*s
   local r=o.r*s
   if o.kind=="gem" then draw_gem(x,y,r)
   else draw_mine(x,y,r,o) end
  end
 end
 for p in all(pops) do
  print(p.txt,p.x-4,p.y,p.life%4<2 and 7 or 11)
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
 for i=1,lives do
  local x=124-(i-1)*9
  trifill(x,7,x-3,12,x+3,12,12)
  pset(x,9,7)
 end
 -- shrink warning
 if rt<minrt+0.6 and t%30<15 then
  print("tunnel critical!",30,118,8)
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
 print("\f6left/right = orbit",30,104,6)
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
__sfx__
00060000244502b450304650000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0004000014673106730c6650865505645000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000a0000213501c35018350133500e355000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000600001f550265502b5660000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000c00000c1300c130131300c1300f1300c130111300c1300c1300c130131300c1301413013130111300f1300c1300c130131300c1300f1300c130111300c1300c13011130131301413016130181301613013130
000c000024720287202b720307202b72028720247201f72024720287202b7203072033720307202b7202872024720287202b720307202b72028720247201f7201f72024720287202b72030720337203772030720
__music__
00 04054041

