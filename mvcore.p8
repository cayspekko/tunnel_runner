pico-8 cartridge // http://www.pico-8.com
version 43
__lua__

-- (untitled) metroidvania
-- movement core / vertical slice
-- by claude + you
--
-- prototype to TUNE THE FEEL before
-- any content. proves the moment-to-
-- moment that the whole game rides on:
--
--   run + variable-height jump
--   coyote time + jump buffering
--   wall-slide + wall-jump (chimney)
--   charge buster (tap=pellet,
--                  hold+release=charged)
--
-- test room exercises all of it.
-- collision is pure-code tile sampling,
-- identical in shape to mget() map
-- collision -- so it ports straight
-- into the real region later.
--
-- controls:
--   arrows = move
--   z (O)  = jump (hold = higher)
--   x (X)  = fire (hold = charge)

-->8
-- config / tunables
-- (this is the dial board -- tweak,
--  run, feel, repeat)

pw=6             -- player hitbox w
ph=7             -- player hitbox h

run_accel=0.5    -- ground accel / frame
run_max=2.0      -- top run speed
run_fric=0.7     -- decel mult when idle

grav=0.3         -- gravity / frame
fall_max=4.0     -- terminal fall speed
jump_v=-4.2      -- initial jump impulse
jump_cut_v=-1.0  -- rising speed clamp
                 -- when jump released
                 -- (variable height)

coyote_max=6     -- frames you can still
                 -- jump after leaving ledge
buffer_max=6     -- frames a jump press is
                 -- remembered before landing

wallslide_max=0.8 -- max fall speed on wall
walljump_vx=2.5   -- launch away from wall
walljump_vy=-4.0  -- launch up off wall
walljump_lock=7   -- frames input is locked
                  -- after a wall-jump

charge_full=30    -- frames to full charge
pellet_dx=3       -- pellet speed
charged_dx=4      -- charged shot speed

-- dash boots (the traversal verb).
-- double-tap a direction to dash; the
-- speed carries into a jump (dash-jump),
-- which is how you clear the wide gate.
dash_speed=4.0    -- dash velocity
dash_frames=10    -- dash duration
dash_cd_extra=8   -- extra cooldown frames
tap_window=12     -- frames to count a
                  -- double-tap as a dash
dash_bleed=0.98   -- momentum bleed when
                  -- holding dir post-dash
                  -- (preserves dash-jump)

-- combat
player_maxhp=4  -- starting max hearts (heart
                -- pickups raise it, see sprite 15)
iframes=48        -- invuln after a hit
hit_knock=2.0     -- knockback x on hit
hit_knock_y=-1.5  -- knockback y on hit
contact_dmg=1     -- touch damage
pellet_dmg=1
charged_dmg=3
walker_spd=0.4    -- basic enemy speed
walker_hp=3

-- boss: the dash guardian (hopper)
boss_hp=20
boss_cd=70        -- frames between hops
boss_tele=18      -- telegraph window pre-hop
boss_hopvx=1.2    -- hop horizontal speed
boss_hopvy=-4.0   -- hop launch
eshot_spd=1.6     -- boss projectile speed
eshot_dmg=1
boss_shoot_cd=50  -- frames between volleys
eshot_spread=0.06 -- max angular miss (turns)
                  -- on the 2 inaccurate shots

-- flyer (bat): homes toward you + shoots
flyer_hp=2
fly_spd=0.5       -- max homing speed
fly_shoot_cd=75   -- frames between shots
fly_shot_spd=1.3

-- jumper (mini-boss foreshadow): walks
-- back+forth like a walker, but hops
jumper_hp=4
jumper_spd=0.4
jumper_jump_cd=75
jumper_hopvx=1.0
jumper_hopvy=-3.6

-- lighting (chunky tile flood, rogue-style).
-- light flows out tile-by-tile, dims with
-- distance, and stops at solid walls (it
-- leaks through doorways -> see a bit into
-- the next room). everything is dark by
-- default. sources: the player + torches.
light_r=7       -- player light radius (tiles)
torch_r=7       -- placed torch radius
light_max=8     -- brightness scale (dimming)
view_r=8        -- how far you can SEE (line of
                -- sight); lit tiles past this
                -- stay hidden. cost grows with
                -- its SQUARE -- keep it modest.

-->8
-- the level (now in the pico-8 MAP)
-- paint it in the MAP EDITOR. collision
-- reads sprite FLAGS:
-- TILE FLAGS (set in the sprite editor):
--   flag 0 = solid (walls + platforms)
--   flag 1 = hazard (spikes / dash-pits)
--   flag 3 = no-cling (solid, but you can't
--            wall-slide/jump off it; spr 2)
-- BOSS DOORS -- a linked pair. walk into one,
-- come out the other:
--   flag 2 = ENTER door (sprite 4) -- works
--            only while the boss is alive
--   flag 4 = EXIT door (sprite 12) -- works
--            only after the boss is dead
--   (both solid; place one in the world, one
--    in the arena. boss wakes when you enter.)
-- MARKER sprites read once at init, then
-- cleared from the map:
--   5=player 6=walker 7=jumper 8=flyer
--   9=boss  10=exit
-- map size is auto-detected (detect_bounds).
mapw=128
maph=32

function tile(c,r)
 if c<0 or c>=mapw or r<0 or r>=maph then
  return true -- level is bounded by walls
 end
 return fget(mget(c,r),0) -- flag 0 = solid
end

-- any tile with flag f under the box?
function box_flag(x,y,w,h,f)
 for c=flr(x/8),flr((x+w-1)/8) do
  for r=flr(y/8),flr((y+h-1)/8) do
   if c>=0 and r>=0 and c<mapw and r<maph
    and fget(mget(c,r),f) then return true end
  end
 end
 return false
end

-- does any solid tile overlap the box
-- (x,y,w,h)?  (used by player + enemies)
function box_solid(x,y,w,h)
 for c=flr(x/8),flr((x+w-1)/8) do
  for r=flr(y/8),flr((y+h-1)/8) do
   if tile(c,r) then return true end
  end
 end
 return false
end

-- is there a CLINGABLE wall in the box?
-- (solid, but NOT a no-cling tile/flag 3)
-- used for wall-slide + wall-jump only, so
-- a no-cling block still blocks movement
-- but you can't grab/jump off it.
function box_wall(x,y,w,h)
 for c=flr(x/8),flr((x+w-1)/8) do
  for r=flr(y/8),flr((y+h-1)/8) do
   if tile(c,r) then
    local nocling=c>=0 and r>=0
     and c<mapw and r<maph
     and fget(mget(c,r),3)
    if not nocling then return true end
   end
  end
 end
 return false
end

-- player-box convenience wrapper
function hits(px,py)
 return box_solid(px,py,pw,ph)
end

-- aabb overlap of two boxes
function overlap(ax,ay,aw,ah,bx,by,bw,bh)
 return ax<bx+bw and ax+aw>bx
  and ay<by+bh and ay+ah>by
end

-- is there a solid tile at a point?
function solid_pt(px,py)
 return tile(flr(px/8),flr(py/8))
end

-- is the player touching a tile with flag f?
-- (a 1px halo, so contact from any side --
-- or standing on top -- counts. lets solid
-- teleport pads trigger without overlap.)
function touching_flag(f)
 return box_flag(p.x-1,p.y-1,pw+2,ph+2,f)
end

-->8
-- init / state

bullets={}
cartdata("dapplegate_glowdeep") -- persistent save
-- save slots: 0 = has_dash, 1+ = heart pickups
-- collected (one slot each). writes persist
-- automatically -> autosave.

function reset_save()
 for i=0,32 do dset(i,0) end
 _init()
end

function _init()
 -- restore the map (markers get mset-cleared
 -- at scan time, so reload before re-scanning)
 reload(0x2000,0x2000,0x1000)
 p={
  x=8, y=8,        -- placeholder; the map
  vx=0, vy=0,      -- marker sets real spawn
  face=1,
  grounded=false,
  wl=false, wr=false,
  spawnx=8, spawny=8,
  safex=8, safey=8, -- last safe ground
                    -- (spikes bounce here)
  -- dash state
  has_dash=false,
  dashing=0,
  dash_dir=1,
  dash_cd=0,
  tap_dir=0,
  tap_t=0,
  plx=false, prx=false,
  -- combat (maxhp can grow via heart pickups)
  hp=player_maxhp,
  maxhp=player_maxhp,
  iframes=0,
  -- the player emits light (toggle off for
  -- "dark room until you get a lamp" beats)
  is_light=true,
  -- ui
  msg="",
  msg_t=0,
 }
 coyote=0
 jbuf=0
 wj_lock=0
 charge=0
 pjb=false
 pfb=false
 camx=0
 camy=0

 enemies={}
 enemy_spawns={}  -- original spawns (to respawn on death)
 items={}
 particles={}
 ebullets={}      -- enemy projectiles
 boss=nil
 -- boss doors (a linked pair). enter door
 -- = flag2, exit door = flag4. you warp
 -- between them; the destination IS the
 -- other door.
 doora={} doorb={}     -- door tile cells
 doora_c=nil doorb_c=nil -- door centers
 tp_cd=0               -- post-warp cooldown

 -- lighting state. these tables are PERSISTENT
 -- (never reallocated) -- entries are tagged
 -- with a generation number instead, so a
 -- recompute allocates ZERO garbage (no GC
 -- spike on every step).
 torches={}            -- static light cells
 lit={} lit_g={}       -- player light + its gen
 tlit={}               -- STATIC torch light
                       -- (world-keyed, baked once)
 seen_g={}             -- LOS gen per tile
 dark={}               -- baked darkness grid
 lvis={}               -- flood visited gen
 lg=0 flg=0            -- recompute / flood gens
 lforce=true           -- force a recompute
 lqc={} lqr={} lqd={}  -- flood-fill scratch

 detect_bounds()  -- map size from content
 -- read player/enemies/boss + teleport
 -- markers from the map
 scan_map()
 spawn_enemies()  -- build the live enemy list
 bake_torches()   -- torches never move, so
                  -- compute their light ONCE

 -- load saved progress
 p.has_dash=dget(0)>0
 p.maxhp=player_maxhp+hearts_got
 p.hp=p.maxhp
 -- the boss reward is the dash, so having it
 -- means the boss is already beaten
 if p.has_dash and boss then boss.alive=false end

 -- pause-menu: wipe save + restart
 menuitem(1,"reset data",function() reset_save() end)
end

-- (re)create all regular enemies from their
-- recorded spawns. called at init + whenever
-- the player dies (the boss is separate, so
-- it isn't respawned here).
function spawn_enemies()
 enemies={}
 for sp in all(enemy_spawns) do
  if sp.kind=="walker" then add(enemies,make_walker(sp.x,sp.y))
  elseif sp.kind=="jumper" then add(enemies,make_jumper(sp.x,sp.y))
  elseif sp.kind=="flyer" then add(enemies,make_flyer(sp.x,sp.y)) end
 end
end

-- auto-size the level from painted tiles,
-- so you never have to set mapw/maph by hand
function detect_bounds()
 mapw=1 maph=1
 for c=0,127 do
  for r=0,31 do
   if mget(c,r)!=0 then
    mapw=max(mapw,c+1)
    maph=max(maph,r+1)
   end
  end
 end
end

-- walk the map; spawn entities at marker
-- sprites (then clear them) and record the
-- teleport destinations + exit-pad cells.
function scan_map()
 heart_n=0      -- index of the next heart found
 hearts_got=0   -- how many already collected (saved)
 for c=0,mapw-1 do
  for r=0,maph-1 do
   local s=mget(c,r)
   local x,y=c*8,r*8
   if s==5 then
    p.x=x p.y=y
    p.spawnx=x p.spawny=y
    p.safex=x p.safey=y
    mset(c,r,0)
   elseif s==6 then
    add(enemy_spawns,{kind="walker",x=x,y=y}) mset(c,r,0)
   elseif s==7 then
    add(enemy_spawns,{kind="jumper",x=x,y=y}) mset(c,r,0)
   elseif s==8 then
    add(enemy_spawns,{kind="flyer",x=x,y=y}) mset(c,r,0)
   elseif s==9 then
    boss=make_boss(x-3,y-6) mset(c,r,0)
   elseif s==10 then
    add(items,{x=x+4,y=y+4,kind="goal",taken=false})
    mset(c,r,0)
   elseif s==15 then
    -- heart container: skip it if already
    -- collected (saved in slot 1+heart_n)
    if dget(1+heart_n)>0 then
     hearts_got+=1
    else
     add(items,{x=x+4,y=y+4,kind="heart",taken=false,hid=heart_n})
    end
    heart_n+=1
    mset(c,r,0)
   elseif s==14 then
    -- torch: a static light source (stays
    -- visible on the map)
    add(torches,{c=c,r=r})
   elseif fget(s,2) then
    -- ENTER door (stays solid): note its cells
    add(doora,{c=c,r=r})
   elseif fget(s,4) then
    -- EXIT door (stays solid): note its cells
    add(doorb,{c=c,r=r})
   end
  end
 end
 doora_c=door_center(doora)
 doorb_c=door_center(doorb)
end

-- average pixel center of a door's tiles
function door_center(cells)
 if #cells==0 then return nil end
 local sx,sy=0,0
 for d in all(cells) do sx+=d.c*8+4 sy+=d.r*8+4 end
 return {x=sx/#cells, y=sy/#cells}
end

-- walk through a door: emerge on the far
-- side of the OTHER door, continuing your
-- direction of travel (so you step out into
-- the new area, not back into the door).
-- flip if that side is blocked; brief
-- cooldown so you don't bounce straight back.
function warp_through(src,dst)
 local side=(p.x+pw/2<src.x) and -1 or 1
 local ex=dst.x-side*8  -- = travel direction
 if box_solid(ex-pw/2,dst.y-ph/2,pw,ph) then
  ex=dst.x+side*8
 end
 p.x=ex-pw/2
 p.y=dst.y-ph/2
 p.vx=0 p.vy=0 p.dashing=0
 p.iframes=iframes
 tp_cd=20
 camx=mid(0,flr(p.x)+flr(pw/2)-64,mapw*8-128)
 camy=mid(0,flr(p.y)+flr(ph/2)-64,maph*8-128)
end

function make_walker(x,y)
 return {
  x=x, y=y, w=6, h=7, kind="walker",
  vx=0, vy=0, grounded=false,
  dir=1, spd=walker_spd,
  hp=walker_hp, maxhp=walker_hp,
  flash=0,
 }
end

function make_jumper(x,y)
 return {
  x=x, y=y, w=8, h=8, kind="jumper",
  vx=0, vy=0, grounded=false, dir=1,
  spd=jumper_spd,
  hp=jumper_hp, maxhp=jumper_hp,
  flash=0, t=jumper_jump_cd,
 }
end

function make_flyer(x,y)
 return {
  x=x, y=y, w=7, h=6, kind="flyer",
  hp=flyer_hp, maxhp=flyer_hp,
  flash=0, t=fly_shoot_cd,
  ph=(x%16)*0.06,  -- bob phase (variety)
 }
end

-- nudge a flyer by (dx,dy), reverting an
-- axis that would enter a wall (no gravity)
function move_fly(e,dx,dy)
 e.x+=dx
 if box_solid(e.x,e.y,e.w,e.h) then e.x-=dx end
 e.y+=dy
 if box_solid(e.x,e.y,e.w,e.h) then e.y-=dy end
end

function make_boss(x,y)
 return {
  x=x, y=y, w=14, h=14,
  homex=x, homey=y,
  -- roams a small arena around its spawn
  xmin=x-28, xmax=x+28,
  vx=0, vy=0, grounded=false, dir=1,
  hp=boss_hp, maxhp=boss_hp,
  flash=0, t=boss_cd, alive=true,
  active=false, -- dormant+invuln until the
                -- boss gate seals you in
  st=30,    -- shoot timer (volley cadence)
  muz=0,    -- muzzle-flash timer
 }
end

-- generic tile physics for an entity with
-- x,y,w,h,vx,vy (sets .grounded). reusable
-- for the boss + future jumping enemies.
function move_entity(e)
 e.x+=e.vx
 if box_solid(e.x,e.y,e.w,e.h) then
  if e.vx>0 then e.x=flr((e.x+e.w-1)/8)*8-e.w
  else e.x=(flr(e.x/8)+1)*8 end
  e.vx=0
 end
 e.grounded=false
 e.y+=e.vy
 if box_solid(e.x,e.y,e.w,e.h) then
  if e.vy>0 then
   e.y=flr((e.y+e.h-1)/8)*8-e.h
   e.grounded=true
  else
   e.y=(flr(e.y/8)+1)*8
  end
  e.vy=0
 end
end

function start_dash(dir)
 p.dashing=dash_frames
 p.dash_dir=dir
 p.face=dir
 p.dash_cd=dash_frames+dash_cd_extra
end

-- axis-separated tile collision.
-- magnitudes stay < 8 so a single
-- snap-to-tile resolve is exact.
function move_x(dx)
 p.x+=dx
 if hits(p.x,p.y) then
  if dx>0 then
   p.x=flr((p.x+pw-1)/8)*8-pw
  else
   p.x=(flr(p.x/8)+1)*8
  end
  p.vx=0
 end
end

function move_y(dy)
 p.y+=dy
 if hits(p.x,p.y) then
  if dy>0 then
   p.y=flr((p.y+ph-1)/8)*8-ph
   p.grounded=true
  else
   p.y=(flr(p.y/8)+1)*8
  end
  p.vy=0
 end
end

-->8
-- update

function _update()
 -- read jump (edge -> fill buffer)
 local jb=btn(4)
 if jb and not pjb then jbuf=buffer_max end

 -- horizontal input
 local ix=0
 if btn(0) then ix=-1
 elseif btn(1) then ix=1 end

 -- double-tap detection -> dash
 local lp=btn(0) and not p.plx
 local rp=btn(1) and not p.prx
 local can_dash=p.has_dash and p.grounded
  and p.dash_cd<=0 and p.dashing<=0
 if lp then
  if p.tap_dir==-1 and p.tap_t>0 and can_dash then
   start_dash(-1)
  end
  p.tap_dir=-1 p.tap_t=tap_window
 elseif rp then
  if p.tap_dir==1 and p.tap_t>0 and can_dash then
   start_dash(1)
  end
  p.tap_dir=1 p.tap_t=tap_window
 end
 p.tap_t=max(p.tap_t-1,0)
 p.dash_cd=max(p.dash_cd-1,0)

 -- resolve horizontal velocity
 if p.dashing>0 then
  -- locked burst at dash speed
  p.vx=p.dash_dir*dash_speed
  p.face=p.dash_dir
  p.dashing-=1
 elseif wj_lock>0 then
  wj_lock-=1
 else
  if ix!=0 then
   p.face=ix
   if abs(p.vx)>run_max and sgn(p.vx)==ix then
    -- above run speed (post-dash): keep
    -- the momentum, bleed slowly -> this
    -- is what makes the dash-jump carry
    p.vx*=dash_bleed
   else
    p.vx=mid(-run_max,p.vx+ix*run_accel,run_max)
   end
  else
   p.vx*=run_fric
   if abs(p.vx)<0.1 then p.vx=0 end
  end
 end

 move_x(p.vx)
 -- wall probes after settling x (clingable
 -- walls only -- no-cling blocks excluded)
 p.wl=box_wall(p.x-1,p.y,pw,ph)
 p.wr=box_wall(p.x+1,p.y,pw,ph)

 -- grounded via a 1px probe below the
 -- feet (only when not rising). this is
 -- what kills the resting jitter: when
 -- grounded we pin vy at 0 instead of
 -- letting gravity drift down a fraction
 -- and snap back every frame.
 p.grounded=p.vy>=0 and hits(p.x,p.y+1)

 -- coyote timer (same frame)
 if p.grounded then
  coyote=coyote_max
 else
  coyote=max(coyote-1,0)
 end

 -- gravity (gated by grounded) + wall-slide
 if p.grounded then
  p.vy=0
 else
  p.vy+=grav
  if p.vy>0 and ((ix<0 and p.wl) or (ix>0 and p.wr)) then
   p.vy=min(p.vy,wallslide_max)
  end
  p.vy=min(p.vy,fall_max)
 end

 -- variable height: clamp rising speed
 -- the moment jump is released
 if not jb and p.vy<jump_cut_v then
  p.vy=jump_cut_v
 end

 -- jump resolution (ground/coyote first,
 -- else wall-jump)
 if jbuf>0 then
  if coyote>0 then
   p.vy=jump_v
   coyote=0
   jbuf=0
   p.grounded=false
  elseif (p.wl or p.wr) and not p.grounded then
   local away=p.wl and 1 or -1
   p.vy=walljump_vy
   p.vx=away*walljump_vx
   p.face=away
   wj_lock=walljump_lock
   jbuf=0
  end
 end
 if jbuf>0 then jbuf-=1 end

 move_y(p.vy)

 -- fire / charge
 local fb=btn(5)
 if fb and not pfb then
  spawn_bullet(false) -- pellet on press
 end
 if fb then
  charge=min(charge+1,charge_full)
 else
  if pfb and charge>=charge_full then
   spawn_bullet(true) -- charged on release
  end
  charge=0
 end

 update_bullets()

 -- pickups (touch to collect)
 for it in all(items) do
  -- dropped items fall + settle on the floor
  if it.fall then
   it.vy=min(it.vy+grav,fall_max)
   it.y+=it.vy
   if it.vy>0 and solid_pt(it.x,it.y+4) then
    it.y=flr((it.y+4)/8)*8-4
    it.vy=0
    it.fall=false
   end
  end
  if not it.taken
   and abs(p.x+pw/2-it.x)<7
   and abs(p.y+ph/2-it.y)<8 then
   it.taken=true
   if it.kind=="dash" then
    p.has_dash=true
    dset(0,1)            -- autosave: got the dash
    p.msg="dash boots! 2-tap a dir"
   elseif it.kind=="heart" then
    -- +1 max heart and refill to full
    p.maxhp+=1
    p.hp=p.maxhp
    dset(1+it.hid,1)     -- autosave: heart taken
    p.msg="heart up! +1 max health"
   else
    p.msg="gate cleared -- world opens"
   end
   p.msg_t=150
  end
 end

 -- boss doors: walk into one, come out the
 -- other. you can ENTER until you've claimed
 -- the boss reward (the boots), and EXIT only
 -- once you HAVE it -- so dying to a stray
 -- shot after the kill can't strand you; just
 -- go back in for the dropped pickup.
 if tp_cd>0 then tp_cd-=1 end
 if tp_cd<=0 and doora_c and doorb_c then
  if not p.has_dash and touching_flag(2) then
   warp_through(doora_c,doorb_c) -- in to arena
   if boss then boss.active=true end
  elseif p.has_dash and touching_flag(4) then
   warp_through(doorb_c,doora_c) -- back out
  end
 end

 -- spikes/dash-pit: bounce back to the last
 -- safe ground + cost 1 hp (no wall to climb,
 -- so a wall-jump can't cheat the gap)
 if p.grounded and not box_flag(p.x,p.y,pw,ph,1) then
  p.safex=p.x p.safey=p.y
 end
 if box_flag(p.x,p.y,pw,ph,1) then
  p.x=p.safex p.y=p.safey
  p.vx=0 p.vy=0 p.dashing=0
  if p.iframes<=0 then
   p.hp-=1 p.iframes=iframes
   p.msg="ouch -- spikes" p.msg_t=60
   if p.hp<=0 then kill_player() end
  end
 end

 -- combat
 if p.iframes>0 then p.iframes-=1 end
 update_enemies()
 update_boss()
 update_ebullets()
 update_particles()

 if p.msg_t>0 then p.msg_t-=1 end

 -- camera follows, clamped to the map.
 -- floored player pos + integer offsets so
 -- the player + world share one pixel grid.
 camx=mid(0,flr(p.x)+flr(pw/2)-64,mapw*8-128)
 camy=mid(0,flr(p.y)+flr(ph/2)-64,maph*8-128)

 pjb=jb
 pfb=fb
 p.plx=btn(0)
 p.prx=btn(1)
end

function spawn_bullet(big)
 add(bullets,{
  x=p.x+(p.face>0 and pw or 0),
  y=p.y+2,
  dx=p.face*(big and charged_dx or pellet_dx),
  big=big,
  life=120,
 })
end

function update_bullets()
 for b in all(bullets) do
  b.x+=b.dx
  b.life-=1
  -- hit an enemy?
  local hit=false
  for e in all(enemies) do
   if overlap(b.x-1,b.y-1,3,3,e.x,e.y,e.w,e.h) then
    hurt_enemy(e,b.big and charged_dmg or pellet_dmg,b.dx)
    hit=true
    break
   end
  end
  -- hit the boss?
  if not hit and boss and boss.alive
   and overlap(b.x-1,b.y-1,3,3,boss.x,boss.y,boss.w,boss.h) then
   hurt_boss(b.big and charged_dmg or pellet_dmg,b.dx)
   hit=true
  end
  if hit
   or b.life<=0
   or solid_pt(b.x,b.y)
   or b.x<0 or b.x>mapw*8 then
   del(bullets,b)
  end
 end
end

-->8
-- combat

function update_enemies()
 for e in all(enemies) do
  if e.flash>0 then e.flash-=1 end

  if e.kind=="jumper" then
   update_jumper(e)
  elseif e.kind=="flyer" then
   update_flyer(e)
  else
   update_walker(e)
  end

  -- contact damage to the player (common)
  if overlap(p.x,p.y,pw,ph,e.x,e.y,e.w,e.h) then
   hurt_player(e.x+e.w/2)
  end
 end
end

-- back-and-forth patrol; turn at wall/ledge
function update_walker(e)
 e.vy=min(e.vy+grav,fall_max)
 if e.grounded then
  -- turn at a wall or a ledge, then walk
  local nx=e.x+e.dir*e.spd
  local lead=e.dir>0 and nx+e.w or nx
  if box_solid(nx,e.y,e.w,e.h)
   or not solid_pt(lead,e.y+e.h+1) then
   e.dir=-e.dir
  end
  e.vx=e.dir*e.spd
 end
 move_entity(e)
end

-- patrols like a walker, but periodically
-- hops toward the player (mini-boss tease)
function update_jumper(e)
 e.vy=min(e.vy+grav,fall_max)
 if e.grounded then
  e.t-=1
  if e.t<=0 then
   e.dir=(p.x<e.x) and -1 or 1
   e.vx=e.dir*jumper_hopvx
   e.vy=jumper_hopvy
   e.grounded=false
   e.t=jumper_jump_cd
  else
   -- walk; turn at wall/ledge
   local nx=e.x+e.dir*e.spd
   local lead=e.dir>0 and nx+e.w or nx
   if box_solid(nx,e.y,e.w,e.h)
    or not solid_pt(lead,e.y+e.h+1) then
    e.dir=-e.dir
   end
   e.vx=e.dir*e.spd
  end
 end
 move_entity(e)
end

-- gently homes toward (and just above) the
-- player, bobs, and fires aimed shots
function update_flyer(e)
 local tx=p.x+pw/2-(e.x+e.w/2)
 local ty=p.y+ph/2-12-(e.y+e.h/2)
 local dx=mid(-fly_spd,tx*0.04,fly_spd)
 local dy=mid(-fly_spd,ty*0.04,fly_spd)
  +sin(t()*0.6+e.ph)*0.5
 move_fly(e,dx,dy)
 if dx!=0 then e.dir=sgn(dx) end
 e.t-=1
 if e.t<=0 then
  aim_eshot(e.x+e.w/2,e.y+e.h/2,fly_shot_spd)
  e.t=fly_shoot_cd
 end
end

-- fire a single aimed enemy bullet
function aim_eshot(cx,cy,spd)
 local a=atan2(p.x+pw/2-cx,p.y+ph/2-cy)
 add(ebullets,{
  x=cx, y=cy,
  dx=cos(a)*spd, dy=sin(a)*spd,
  life=150,
 })
end

function hurt_enemy(e,dmg,bdx)
 e.hp-=dmg
 e.flash=5
 e.x+=sgn(bdx)*2 -- small knockback
 if e.hp<=0 then
  spawn_particles(e.x+e.w/2,e.y+e.h/2,8)
  del(enemies,e)
 end
end

function update_boss()
 local b=boss
 if not b or not b.alive then return end
 if b.flash>0 then b.flash-=1 end
 if b.muz>0 then b.muz-=1 end

 b.vy=min(b.vy+grav,fall_max)

 -- dormant until the gate seals you in:
 -- just settle on the floor, no attacks
 if not b.active then
  b.vx*=0.8
  move_entity(b)
  return
 end

 -- hop movement
 b.t-=1
 if b.grounded then
  b.vx*=0.7  -- settle between hops
  if b.t<=0 then
   -- leap toward the player
   b.dir=(p.x<b.x) and -1 or 1
   b.vx=b.dir*boss_hopvx
   b.vy=boss_hopvy
   b.grounded=false
   b.t=boss_cd
  end
 end

 -- shooting: a 3-shot shotgun on its own
 -- cadence, fired from the boss's CURRENT
 -- position (ground or mid-air)
 b.st-=1
 if b.st<=0 then
  boss_shoot(b)
  b.st=boss_shoot_cd
  b.muz=5
 end

 move_entity(b)

 -- the arena WALLS contain the boss now
 -- (no artificial clamp). failsafe only:
 if b.y>maph*8 then
  b.x=b.homex b.y=b.homey
  b.vx=0 b.vy=0 b.grounded=false
 end

 if overlap(p.x,p.y,pw,ph,b.x,b.y,b.w,b.h) then
  hurt_player(b.x+b.w/2)
 end
end

-- 3-shot shotgun aimed at the player. one
-- shot is dead-on; the other two miss by a
-- random angle. WHICH one is accurate is
-- random each volley -> you must read it
-- fast and move (camping = the accurate
-- shot finds you).
function boss_shoot(b)
 local cx,cy=b.x+b.w/2,b.y+b.h/2
 local base=atan2(p.x+pw/2-cx,p.y+ph/2-cy)
 local acc=flr(rnd(3)) -- 0,1,2: the true one
 for i=0,2 do
  local a=base
  if i!=acc then
   -- random miss to either side
   local off=rnd(eshot_spread)+eshot_spread/2
   a+=(rnd(1)<0.5) and off or -off
  end
  add(ebullets,{
   x=cx, y=cy,
   dx=cos(a)*eshot_spd,
   dy=sin(a)*eshot_spd,
   life=140,
  })
 end
end

function update_ebullets()
 for q in all(ebullets) do
  q.x+=q.dx q.y+=q.dy q.life-=1
  if overlap(q.x-1,q.y-1,3,3,p.x,p.y,pw,ph) then
   hurt_player(q.x)
   del(ebullets,q)
  elseif q.life<=0 or solid_pt(q.x,q.y) then
   del(ebullets,q)
  end
 end
end

function hurt_boss(dmg,bdx)
 local b=boss
 if not b.active then return end -- invuln till sealed in
 b.hp-=dmg
 b.flash=5
 if b.hp<=0 then
  b.alive=false
  ebullets={} -- clear stray shots so you
              -- can't die right after the kill
  -- big burst
  spawn_particles(b.x+b.w/2,b.y+b.h/2,8)
  spawn_particles(b.x+3,b.y+3,10)
  spawn_particles(b.x+b.w-3,b.y+b.h-3,10)
  -- DROP the boots: they pop up + fall to
  -- the floor for you to walk over and claim
  -- (more dramatic than an instant award)
  add(items,{
   x=b.x+b.w/2, y=b.y+b.h/2,
   kind="dash", taken=false,
   vy=-2.5, fall=true,
  })
  p.msg="the guardian drops something..."
  p.msg_t=150
 end
end

function hurt_player(srcx)
 if p.iframes>0 then return end
 p.hp-=contact_dmg
 p.iframes=iframes
 -- knock away from the source
 local dir=(p.x+pw/2<srcx) and -1 or 1
 p.vx=dir*hit_knock
 p.vy=hit_knock_y
 p.dashing=0
 if p.hp<=0 then kill_player() end
end

function kill_player()
 -- respawn + refill (slice behavior;
 -- a real checkpoint comes later)
 p.x=p.spawnx p.y=p.spawny
 p.vx=0 p.vy=0 p.dashing=0
 p.hp=p.maxhp
 p.iframes=iframes
 p.msg="you died -- respawned"
 p.msg_t=90
 -- all regular enemies come back
 spawn_enemies()
 -- reset the boss so the arena is a clean
 -- retry (dying boots you out to spawn)
 if boss and boss.alive then
  boss.hp=boss.maxhp
  boss.active=false
  boss.x=boss.homex boss.y=boss.homey
  boss.vx=0 boss.vy=0
 end
 ebullets={}
end

function spawn_particles(x,y,col)
 for i=1,7 do
  add(particles,{
   x=x, y=y,
   dx=rnd(3)-1.5,
   dy=rnd(3)-2,
   life=10+rnd(10),
   col=col,
  })
 end
end

function update_particles()
 for q in all(particles) do
  q.dy+=0.2
  q.x+=q.dx
  q.y+=q.dy
  q.life-=1
  if q.life<=0 then del(particles,q) end
 end
end

-->8
-- lighting (chunky tile flood)

-- recompute the light grid only when the
-- player or camera moves to a new tile
function update_light()
 local pc,pr=flr((p.x+pw/2)/8),flr((p.y+ph/2)/8)
 local cc,cr=flr(camx/8),flr(camy/8)
 if not lforce
  and pc==llpc and pr==llpr
  and cc==llcc and cr==llcr then return end
 llpc=pc llpr=pr llcc=cc llcr=cr lforce=false
 compute_light(cc,cr)
end

function compute_light(cc,cr)
 -- window covers the screen + a view margin
 local m=view_r+1
 lgc0=cc-m lgr0=cr-m
 lgw=16+m*2 lgh=16+m*2
 lg+=1  -- new recompute generation (invalidates
        -- last frame's lit/seen with no realloc)
 -- only the (moving) player floods per step;
 -- torch light is baked once (see get_lit)
 if p.is_light then
  flood(flr((p.x+pw/2)/8),flr((p.y+ph/2)/8),view_r,light_r,true)
 end
 -- bake per-tile darkness for the screen ONCE
 for r=cr,cr+16 do
  for c=cc,cc+16 do
   local lv
   if is_opaque(c,r) then
    lv=0
    for ni=1,8 do local nb=nbrs[ni]
     if seen_at(c+nb[1],r+nb[2]) then
      lv=max(lv,get_lit(c+nb[1],r+nb[2]))
     end
    end
   else
    lv=seen_at(c,r) and get_lit(c,r) or 0
   end
   dark[(r-lgr0)*lgw+(c-lgc0)]=
    mid(0,flr((light_max-lv)*5/light_max)-1,4)
  end
 end
end

-- BFS through OPEN tiles (walls block + are
-- never entered), hand-inlined + zero-alloc.
-- marks seen (if ms) out to rng, lights floors
-- out to lr. walls take brightness from visible
-- floors at draw time (no bleed-through).
nbrs={{-1,0},{1,0},{0,-1},{0,1},
      {-1,-1},{1,-1},{-1,1},{1,1}}
function flood(sc,sr,rng,lr,ms)
 flg+=1
 local g=flg
 lvis[sc+sr*1024]=g
 lqc[1]=sc lqr[1]=sr lqd[1]=0
 local h,qn=1,1
 while h<=qn do
  local c,r,d=lqc[h],lqr[h],lqd[h] h+=1
  local idx=(r-lgr0)*lgw+(c-lgc0)
  if ms then seen_g[idx]=lg end
  if d<lr then
   local lv=lr-d
   if lit_g[idx]!=lg or lit[idx]<lv then
    lit[idx]=lv lit_g[idx]=lg
   end
  end
  if d<rng then
   local nd=d+1
   for ni=1,8 do local nb=nbrs[ni]
    local nc,nr=c+nb[1],r+nb[2]
    if nc>=lgc0 and nr>=lgr0
     and nc<lgc0+lgw and nr<lgr0+lgh then
     local k=nc+nr*1024
     if lvis[k]!=g then
      -- opaque? (out of map = solid wall)
      local op
      if nc<0 or nr<0 or nc>=mapw or nr>=maph then
       op=true
      else
       op=fget(mget(nc,nr),0)
      end
      if not op then
       lvis[k]=g
       qn+=1 lqc[qn]=nc lqr[qn]=nr lqd[qn]=nd
      end
     end
    end
   end
  end
 end
end

-- bake every torch's light into tlit (world
-- keyed) ONCE -- torches never move, so this
-- never runs again. per-step cost is then
-- independent of how many torches you place.
function bake_torches()
 tlit={}
 for tt in all(torches) do
  flood_torch(tt.c,tt.r,torch_r)
 end
end

function flood_torch(sc,sr,rad)
 flg+=1
 local g=flg
 lvis[sc+sr*1024]=g
 lqc[1]=sc lqr[1]=sr lqd[1]=0
 local h,qn=1,1
 while h<=qn do
  local c,r,d=lqc[h],lqr[h],lqd[h] h+=1
  local k=c+r*1024
  local lv=rad-d
  if (tlit[k] or 0)<lv then tlit[k]=lv end
  if d<rad then
   local nd=d+1
   for ni=1,8 do local nb=nbrs[ni]
    local nc,nr=c+nb[1],r+nb[2]
    local k2=nc+nr*1024
    if lvis[k2]!=g then
     local op
     if nc<0 or nr<0 or nc>=mapw or nr>=maph then
      op=true
     else
      op=fget(mget(nc,nr),0)
     end
     if not op then
      lvis[k2]=g
      qn+=1 lqc[qn]=nc lqr[qn]=nr lqd[qn]=nd
     end
    end
   end
  end
 end
end

-- brightest of the player's (dynamic) light
-- and the torches' (static) baked light
function get_lit(c,r)
 local v=tlit[c+r*1024] or 0
 if c>=lgc0 and r>=lgr0
  and c<lgc0+lgw and r<lgr0+lgh then
  local i=(r-lgr0)*lgw+(c-lgc0)
  if lit_g[i]==lg and lit[i]>v then v=lit[i] end
 end
 return v
end

function seen_at(c,r)
 if c<lgc0 or r<lgr0
  or c>=lgc0+lgw or r>=lgr0+lgh then return false end
 return seen_g[(r-lgr0)*lgw+(c-lgc0)]==lg
end

function is_opaque(c,r) return tile(c,r) end

-- darkness dither, index = darkness level
-- [1]=clear .. [5]=solid black.
-- NOTE: with fillp(p+0.5), the pattern's
-- 1-bits are TRANSPARENT and 0-bits draw
-- black -- so MORE 0-bits = darker. hence
-- this ramps from all-1s (clear) to all-0s.
darkpat={0xffff,0xfdfd,0xa5a5,0x0840,0x0000}
-- read the cached darkness grid + draw it as
-- merged horizontal RUNS (one rectfill per run
-- of equal darkness) -> far fewer draw calls.
-- (+0.5 on fillp = transparency: 1-bits show
--  through, 0-bits draw black.)
function draw_dark()
 local c0,r0=flr(camx/8),flr(camy/8)
 for r=r0,r0+16 do
  local base=(r-lgr0)*lgw-lgc0
  local c=c0
  while c<=c0+16 do
   local d=dark[base+c] or 4
   if d<=0 then
    c+=1
   else
    local c2=c
    while c2<c0+16 and (dark[base+c2+1] or 4)==d do
     c2+=1
    end
    fillp(darkpat[d+1]+0.5)
    rectfill(c*8,r*8,c2*8+7,r*8+7,0)
    c=c2+1
   end
  end
 end
 fillp()
end

-->8
-- draw

function _draw()
 cls(0)
 update_light()
 camera(camx,camy)

 draw_room()
 draw_items()
 draw_enemies()
 draw_boss()
 draw_bullets()
 draw_ebullets()
 draw_particles()
 draw_player()
 draw_dark()      -- darkness overlay (world)

 camera()
 draw_hud()
 draw_msg()
end

function draw_room()
 -- draw ONLY the on-screen tiles (~17x17),
 -- not the whole map. cost is now constant
 -- no matter how big the level gets.
 local c0,r0=flr(camx/8),flr(camy/8)
 map(c0,r0,c0*8,r0*8,17,17)
 -- the exit door lights up once you have the
 -- boots (i.e. the exit is now usable)
 if p.has_dash then
  local col=(flr(t()*4)%2==0) and 11 or 7
  for d in all(doorb) do
   rect(d.c*8,d.r*8,d.c*8+7,d.r*8+7,col)
  end
 end
end

function draw_player()
 -- blink while invincible after a hit
 if p.iframes>0 and p.iframes%4<2 then return end
 -- floor to match the camera's pixel grid
 local x,y=flr(p.x),flr(p.y)
 -- dash afterimages (trail)
 if p.dashing>0 then
  for i=1,3 do
   local gx=x-p.dash_dir*i*3
   rectfill(gx,y,gx+pw-1,y+ph-1,i==1 and 13 or 1)
  end
 end
 -- body
 rectfill(x,y,x+pw-1,y+ph-1,12)
 rectfill(x,y,x+pw-1,y+1,7) -- helmet shine
 -- eye (facing)
 local ex=p.face>0 and x+pw-2 or x+1
 pset(ex,y+2,0)
 -- charge glow at muzzle
 if charge>=8 then
  local mx=p.face>0 and x+pw or x
  local r=charge>=charge_full and 3 or 2
  local col=charge>=charge_full and 10 or 7
  circ(mx,y+3,r+(t()*20%2),col)
 end
end

function draw_items()
 for it in all(items) do
  if not it.taken then
   local bob=it.fall and 0 or sin(t())*1.5
   local x,y=it.x,it.y+bob
   if it.kind=="dash" then
    -- glowing boots pickup
    circfill(x,y,4,(flr(t()*4)%2==0) and 9 or 10)
    rectfill(x-2,y-1,x+2,y+2,12)
    pset(x-2,y+2,7) pset(x+2,y+2,7)
   elseif it.kind=="heart" then
    -- glowing heart container
    circfill(x,y,5,(flr(t()*4)%2==0) and 2 or 8)
    spr(15,x-4,y-4)
   else
    -- goal flag (far side of the gate)
    rectfill(x,y-6,x,y+4,6)
    rectfill(x+1,y-6,x+5,y-2,11)
   end
  end
 end
end

function draw_enemies()
 for e in all(enemies) do
  local x,y=flr(e.x),flr(e.y)
  if e.kind=="flyer" then
   draw_flyer(e,x,y)
  elseif e.kind=="jumper" then
   draw_jumper(e,x,y)
  else
   draw_walker(e,x,y)
  end
  enemy_hp_pips(e,x,y)
 end
end

function draw_walker(e,x,y)
 local body=e.flash>0 and 7 or 8
 rectfill(x,y,x+e.w-1,y+e.h-1,body)
 local ex=e.dir>0 and x+e.w-2 or x+1
 pset(ex,y+2,0)
 pset(x,y+e.h-1,2) pset(x+e.w-1,y+e.h-1,2)
end

-- mini-boss tease: echoes the boss palette
-- (purple body, red crown) but pint-sized
function draw_jumper(e,x,y)
 local body=e.flash>0 and 7 or 2
 rectfill(x,y,x+e.w-1,y+e.h-1,body)
 rectfill(x+1,y+1,x+e.w-2,y+2,8) -- crown
 local ex=e.dir>0 and x+e.w-3 or x+1
 pset(ex,y+4,7) pset(ex+1,y+4,7)
end

function draw_flyer(e,x,y)
 local body=e.flash>0 and 7 or 14
 -- flapping wings
 local f=(flr(t()*8)%2==0) and -1 or 1
 line(x,y+2+f,x-1,y+1,2)
 line(x+e.w-1,y+2+f,x+e.w,y+1,2)
 rectfill(x+1,y+1,x+e.w-2,y+e.h-1,body)
 pset(x+2,y+2,8) pset(x+e.w-3,y+2,8) -- eyes
end

function enemy_hp_pips(e,x,y)
 if e.hp<e.maxhp then
  for i=1,e.maxhp do
   pset(x+i-1,y-2,i<=e.hp and 11 or 5)
  end
 end
end

function draw_particles()
 for q in all(particles) do
  pset(flr(q.x),flr(q.y),q.col)
 end
end

function draw_boss()
 local b=boss
 if not b or not b.alive then return end
 local x,y=flr(b.x),flr(b.y)
 local col=2 -- dark body
 if b.flash>0 then col=7 end
 -- telegraph: pulse red just before a hop
 if b.grounded and b.t<boss_tele and b.t%4<2 then
  col=8
 end
 rectfill(x,y,x+b.w-1,y+b.h-1,col)
 rectfill(x+1,y+1,x+b.w-2,y+3,8) -- crown band
 -- eyes (look toward travel dir)
 local ey=y+6
 rectfill(x+3,ey,x+4,ey+1,7)
 rectfill(x+b.w-5,ey,x+b.w-4,ey+1,7)
 local px=b.dir<0 and 0 or 1
 pset(x+3+px,ey,0) pset(x+b.w-5+px,ey,0)
 -- muzzle flash (shots originate here)
 if b.muz>0 then
  local mx,my=x+b.w/2,y+b.h/2
  circfill(mx,my,3,10)
  circfill(mx,my,1,7)
 end
end

function draw_ebullets()
 for q in all(ebullets) do
  circfill(flr(q.x),flr(q.y),1,8)
  pset(flr(q.x),flr(q.y),10)
 end
end

function draw_msg()
 if p.msg_t>0 then
  local w=#p.msg*4
  rectfill(63-w/2-2,101,64+w/2+1,109,0)
  print(p.msg,64-w/2,103,10)
 end
end

function draw_bullets()
 for b in all(bullets) do
  local bx,by=flr(b.x),flr(b.y)
  if b.big then
   circfill(bx,by,2,10)
   circ(bx,by,2,7)
  else
   circfill(bx,by,1,7)
  end
 end
end

function draw_hud()
 -- perf meter (read the REAL number on your
 -- machine). cpu>100% = over budget = laggy.
 local cpu=flr(stat(1)*100)
 print("cpu "..cpu.."%",96,2,cpu>90 and 8 or 11)

 -- state readout for tuning
 local st="air"
 if p.grounded then st="ground"
 elseif (p.wl or p.wr) then st="wall" end
 print("state:"..st,2,2,7)
 print("vx:"..flr(p.vx*10)/10,2,9,6)
 print("vy:"..flr(p.vy*10)/10,2,16,6)
 print("dash:"..(p.has_dash and "on" or "--"),2,23,p.has_dash and 11 or 5)

 -- charge meter
 if charge>0 then
  local w=charge/charge_full*40
  rect(85,3,126,7,5)
  rectfill(86,4,86+w,6,charge>=charge_full and 10 or 7)
 end

 -- hearts (count grows with heart pickups)
 for i=1,p.maxhp do
  draw_heart(44+(i-1)*7,2,i<=p.hp)
 end

 -- boss hp bar -- only while the fight is ON
 -- (boss.active = you teleported in + woke it;
 -- it's dormant/hidden until then)
 if boss and boss.alive and boss.active then
  rectfill(0,122,127,127,0)
  print("dash guardian",2,123,8)
  rect(53,123,126,126,5)
  rectfill(54,124,54+71*boss.hp/boss.maxhp,125,8)
 else
  print("\151jump  \142fire",2,122,13)
 end
end

function draw_heart(x,y,full)
 local c=full and 8 or 5
 pset(x,y,c) pset(x+1,y,c)
 pset(x+3,y,c) pset(x+4,y,c)
 rectfill(x,y+1,x+4,y+1,c)
 rectfill(x+1,y+2,x+3,y+2,c)
 pset(x+2,y+3,c)
end
__gfx__
0000000066666666dddddddd0000000099999999bbbbbbbb8888888822222222eeeeeeee44444444cccccccc3333333300000000111111110009900000000000
0000000055555555c7cccccc8080080894444449bbbbbbbb8888888822222222eeeeeeee44444444cccccccc333333330bbbbbb0111111110009a90008800880
0000000055555555cccccccc8888888894999949bbbbbbbb8888888822222222eeeeeeee44444444cccccccc333333330b0000b011111111009aaa9087788888
0000000055555555cccccccc8888888894999949bbb00bbb8880088822200222eee00eee44400444ccc00ccc333003330b0000b01110011109aaaa9088888888
0000000055555555cccccccc8788887894999949bbb00bbb8880088822200222eee00eee44400444ccc00ccc333003330b0000b011100111009aaa9008888880
0000000055555555cccccccc8888888894999949bbbbbbbb8888888822222222eeeeeeee44444444cccccccc333333330b0000b0111111110009a90000888800
0000000055555555cccccccc8888888894444449bbbbbbbb8888888822222222eeeeeeee44444444cccccccc333333330bbbbbb0111111110004400000088000
0000000055555555cccccccc8888888899999999bbbbbbbb8888888822222222eeeeeeee44444444cccccccc3333333300000000111111110004400000000000
__label__
66666666666666666666666666666666666666666666666666666666666666666666666600000000666666666666666666666666666666666666666666666666
55555555555555555555555555555555550555055555555555555555555555555555555500000000550555055555555555555555555555555555555555555555
55577577757775777577755555577577755775757577887885588588558858855885885588088000555555555555555555555555555555555555555555555555
55755557557575575575555755755575757575757575888885588888558888855888885588888000550555055555555555555555555555555555555555555555
55777557557775575577555555755577557575757575788875558885555888555588855508880000555555555555555555555555555555555555555555555555
55557557557575575575555755757575757575757575758575555855555585555558555500800000550555055555555555555555555555555555555555555555
55775557557575575577755555777575757755577575757775555555555555555555555500000000555555555555555555555555555555555555555555555555
55555555555555555555555555555555550555055555555555555555555555555555555500000000550555055555555555555555555555555555555555555555
00000000000000000000000000000000000000000000000000000000000000000000000066666666000000000000000000000000000000000000000000000000
00606060600000666000000000000000000000000000000000000000000000000000000055555555000000000000000000000000000000000000000000000000
00606060600600606000000000000000000000000000000000000000000000000000000055555555000000000000000000000000000000000000000000000000
00606006000000606000000000000000000000000000000000000000000000000000000055555555000000000000000000000000000000000000000000000000
00666060600600606000000000000000000000000000000000000000000000000000000055555555000000000000000000000000000000000000000000000000
00060060600000666000000000000000000000000000000000000000000000000000000055555555000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000055555555000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000055555555000000000000000000000000000000000000000000000000
00606060600990666000000000000000000000000000000000000000000990000000000000000000000000000000000000000000000990000000000000000000
006060606006a96060000000000000000000000000000000000000000009a90000022eeeee2200000000000000000000000000000009a9000000000000000000
00606066609aaa606000000000000000000000000000000000000000009aaa9000000e8e8e000000000000000000000000000000009aaa900000000000000000
0066600069a6aa60600000000000000000000000000000000000000009aaaa9000000eeeee00000000000000000000000000000009aaaa900000000000000000
00060066609aaa666000000000000000000000000000000000000000009aaa9000000eeeee000000000000000000000000000000009aaa900000000000000000
000000000009a90000000000000000000000000000000000000000000009a90000000eeeee0000000000000000000000000000000009a9000000000000000000
00000000000440000000000000000000000000000000000000000000000440000000000000000000000000000000000000000000000440000000000000000000
00550055500550505000000000000000000000000000000000000000000440000000000000000000000000000000000000000000000440000000000000000000
00505050505000505005000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00505055505550555000005550555000000000007777770000000000000000000000000000000000000000000000000000000000000000000000000000000000
00505050500050505005000000000000000000007777770000000000000000000000000000000000000000000000000000000000000000000000000000000000
0055505050550050500000000000000000000000cccc0c0000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000cccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000cccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000cccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000cccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000
66666666666666666666666666666666666666666666666600000000000000000000000000000000000000000000000000000000dddddddd6666666666666666
55555555555555555555555555555555555555555555555500000000000000000000000000000000000000000000000000000000c7cccccc5555555555555555
55555555555555555555555555555555555555555555555500000000000000000000000000000000000000000000000000000000cccccccc5555555555555555
55555555555555555555555555555555555555555555555500000000000000000000000000000000000000000000000000000000cccccccc5555555555555555
55555555555555555555555555555555555555555555555500000000000000000000000000000000000000000000000000000000cccccccc5555555555555555
55555555555555555555555555555555555555555555555500000000000000000000000000000000000000000000000000000000cccccccc5555555555555555
55555555555555555555555555555555555555555555555500000000000000000000000000000000000000000000000000000000cccccccc5555555555555555
55555555555555555555555555555555555555555555555500000000000000000000000000000000000000000000000000000000cccccccc5555555555555555
66666666000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000dddddddd0000000000000000
55055505000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c70ccc0c0000000000000000
55555555000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cccccccc0000000000000000
55055505000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cc0ccc0c0000000000000000
55555555000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cccccccc0000000000000000
55055505000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cc0ccc0c0000000000000000
55555555000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cccccccc0000000000000000
55055505000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cc0ccc0c0000000000000000
66666666000000000000000000099000000000000000000000000000000000000000000000099000000000000000000000000000d0d0d0d00000000000000000
5505550500000000000000000009a90000000000000000000000000000000000000000000009a900000000000000000000000000070c0c0c0000000000000000
555555550000000000000000009aaa900000000000000000000000000000000000000000009aaa90000000000000000000000000c0c0c0c00000000000000000
55055505000000000000000009aaaa90000000000000000000000000000000000000000009aaaa900000000000000000000000000c0c0c0c0000000000000000
555555550000000000000000009aaa900000000000000000000000000000000000000000009aaa90000000000000000000000000c0c0c0c00000000000000000
5505550500000000000000000009a90000000000000000000000000000000000000000000009a9000000000000000000000000000c0c0c0c0000000000000000
55555555000000000000000000044000000000000000000000000000000000000000000000044000000000000000000000000000c0c0c0c00000000000000000
550555050000000000000000000440000000000000000000000000000000000000000000000440000000000000000000000000000c0c0c0c0000000000000000
66666666000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d0d0d0d00000000000000000
55055505000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000070c0c0c0000000000000000
55555555000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0c0c0c00000000000000000
550555050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0c0c0c0000000000000000
55555555000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0c0c0c00000000000000000
550555050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0c0c0c0000000000000000
55555555000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0c0c0c00000000000000000
550555050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0c0c0c0000000000000000
66666666000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d0d0d0d00000000000000000
55055505000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000070c0c0c0000000000000000
55555555000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0c0c0c00000000000000000
550555050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0c0c0c0000000000000000
55555555000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0c0c0c00000000000000000
550555050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0c0c0c0000000000000000
55555555000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0c0c0c00000000000000000
550555050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c0c0c0c0000000000000000
66666666000000000000000000000000000000000000000066666666666666666666666666666666666666666666666666666666000000000000000000000000
55055505000000000000000000000000000000000000000055055505550555055505550555055505550555055505550555055505000000000000000000000000
55555555000000000000000000000000000000000000000055555555555555555555555555555555555555555555555555555555000000000000000000000000
55055505000000000000000000000000000000000000000055055505550555055505550555055505550555055505550555055505000000000000000000000000
55555555000000000000000000000000000000000000000055555555555555555555555555555555555555555555555555555555000000000000000000000000
55055505000000000000000000000000000000000000000055055505550555055505550555055505550555055505550555055505000000000000000000000000
55555555000000000000000000000000000000000000000055555555555555555555555555555555555555555555555555555555000000000000000000000000
55055505000000000000000000000000000000000000000055055505550555055505550555055505550555055505550555055505000000000000000000000000
60606060000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
05050505000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
50505050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
05050505000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
50505050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
05050505000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
50505050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
05050505000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
60606060000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
05050505000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
50505050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
05050505000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
50505050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
05050505000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
50505050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
05050505000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
50005000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
05000500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
50005000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
05000500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
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
00880088800880808000000880808088808880880088808880880555555555555555555555555555555555555555555555555555555555555555555555555550
00808080808000808000008000808080808080808008008080808588888888888888888888888888888888888888888888888888888888888888888888888850
00808088808880888000008000808088808800808008008880808588888888888888888888888888888888888888888888888888888888888888888888888850
00808080800080808000008080808080808080808008008080808555555555555555555555555555555555555555555555555555555555555555555555555550
00888080808800808000008880088080808080888088808080808000000000000000000000000000000000000000000000000000000000000000000000000000

__gff__
0001090205000000000000001100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000010000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000001
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000e000000000000000000000000000000000e000800000000000800000e00000000010f00000000000000000e000000000000000000060000000e000000000000000001
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000008000000000000000000000000000000000000000000000001010100000000020000000000000000000000020202000000000000000000000001
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000101010101010101000000000000000201010101000000000000000000000000000000000001000000000000020000000000020000000000000000000000000006000000000001
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000010000000000000000000000000200000000000000010000000000010000000101000001000000000000020000000000020000000000000000000000000202020100000001
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010600000001000000000000000e000000000200000000000000010000000000010000000001000001000001010000000000000000020000000000000000000000000000000100000001
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000101010000010000000000000000000000000200000000000000010000000000010000000001000001000000000000000000000000000000000000000000000000000000000100000001
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010e000000010000000000000000000000000200000000000000000000000000000000000001000001000000000000000000000000000000000000000000000000000000000000000001
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000108000000010000000000010101010101010100000000000000000000000000000000000001000001000000000000000000000000000000000000000000000008000000000000000001
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000010000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000001
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000100000e000000000000000000000e00000000000000000000000e0000000000000000010000000000000e00000000080000000000000e0000000000000000000e00000001
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000001010000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000001
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000001040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000001040000000000070000000007000000000007000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000001010101010101010101010101010101010101010101010103030303030303030101010101010101030303030303030303010103030303030303030301010303030303030301
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000008010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000010000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000010000000e00000000000000000e00000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000010000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010600000001000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010101000001090000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010e000000010101010101010101010101010101010101000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000006010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000101010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100050000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000101010101010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000