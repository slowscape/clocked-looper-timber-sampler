-- clocked 4 track looper with sample player (timber)
-- for use with a beatstep pro (drum channel).

-- Load & edit samples in EDIT menu
-- E1 = Select Voice
-- E2 = Select Level or Rate
-- E3 = Set selected value
-- K2 = Overdub / play
-- K3 = Record / Play
-- K1 + E3 = Change BPM (if not MIDI controlled)
--

local cs = require 'controlspec'
local state = {"stop","stop","stop","stop"}
local start_time = {0,0,0,0}
local loop_len = {0,0,0,0}
local s1 = 1
local s2 = 1

-- button presses
local modd = false
local recOff = false
local recOn = false
local odOff = false
local odOn = false

-- tempo related
local daBeat = 1
local temp0 = 120

params:set("clock_tempo",temp0)

---------------------------------
-- TImbeR

--TIMBER controls
local timber = include("timber/lib/timber_engine")
local MusicUtil = require "musicutil"
--local UI = require "ui"
local Formatters = require "formatters"
local fileselect = require "fileselect"

engine.name = "Timber"
num_samples = 52

local options = {}
options.OFF_ON = {"Off", "On"}

local sample_status = {}
local STATUS = {
  STOPPED = 0,
  STARTING = 1,
  PLAYING = 2,
  STOPPING = 3
}

local current_sample_id = 0

local midi_in_device
local midi_clock_in_device
local grid_device

-- timber stuff

function load_folder(file, add)
  local sample_id = 36
  local split_at = string.match(file, "^.*()/")
  local folder = string.sub(file, 1, split_at)
  file = string.sub(file, split_at + 1)

  if add then
    for i = timber.num_samples - 1, 0, -1 do
      if timber.samples_meta[i].num_frames > 0 then
        sample_id = i + 1
        print("sAMPLEiD: ",sample_id)
        break
      end
    end
  end

  timber.clear_samples(sample_id, num_samples - 1)

  local found = false
  for k, v in ipairs (fileselect.list) do
    if v == file then found = true end
    if found then
      if sample_id > (num_samples - 1) then
        print("Max files loaded")
        break
      end
      -- Check file type
      local lower_v = v:lower()
      if string.find(lower_v, ".wav") or string.find(lower_v, ".aif") or string.find(lower_v, ".aiff") then
        print("Loading samples", folder .. v, sample_id, audio.file_info(folder .. v))
        timber.load_sample(sample_id, folder .. v)
        params:set("play_mode_" .. sample_id, 4) -- doesnt do anything?
        sample_id = sample_id + 1
        print("sAMPLEiD: ",sample_id)
      else
        print("Skipped", v)
      end
    end
  end
end

function add_params()
  params:add_separator("TIMBERR")

  params:add_trigger("load_t", "+ Load Timber samples")
  params:set_action("load_t", function()
    timber.FileSelect.enter(_path.audio,  function(file)
      if file ~= "cancel" then
        load_folder(file, add)
      end
    end)
  end)
  params:add_separator("In/Out")
  params:add{type = "number", id = "midi_in_device", name = "MIDI In Device", min = 1, max = 4, default = 1, action = reconnect_midi_ins}
  local channels = {"All"}
  for i = 1, 16 do table.insert(channels, i) end
  params:add{type = "option", id = "midi_in_channel", name = "MIDI In Channel", options = channels}
    
  params:add{type = "number", id = "midi_clock_in_device", name = "MIDI Clock In Device", min = 1, max = 4, default = 1, action = reconnect_midi_ins}
  
  params:add_separator("Player")
    
  params:add{type = "number", id = "bend_range", name = "Pitch Bend Range", min = 1, max = 48, default = 2}
  
  params:add{type = "trigger", id = "launch_mode_all_one_shot", name = "Launch Mode: All One shot", action = function()
    for i = 36, num_samples - 1 do
      params:set("play_mode_" .. i, 4)
    end
  end}
  params:add{type = "trigger", id = "launch_mode_all_loop", name = "Launch Mode: All Loop", action = function()
    for i = 36, num_samples - 1 do
      params:set("play_mode_" .. i, 1)
    end
  end}
  params:add{type = "trigger", id = "quality_all_nasty", name = "Quality: All Nasty", action = function()
    for i = 36, num_samples - 1 do
      params:set("quality_" .. i, 1)
    end
  end}
  params:add{type = "trigger", id = "quality_all_high", name = "Quality, All High", action = function()
    for i = 36, num_samples - 1 do
      params:set("quality_" .. i, 4)
    end
  end}
  
  params:add_separator()
  -- Index zero to align with MIDI note numbers
  for i = 36, num_samples - 1 do
    local extra_params = {
      {type = "option", id = "launch_mode_" .. i, name = "Launch Mode", options = {"Gate", "Toggle"}, default = 1, action = function(value)
        timber.setup_params_dirty = true
      end}
    }
    timber.add_sample_params(i, true, extra_params)
  end
end

-- TIMBER CoNTROLLS

local function queue_note_event(event_type, sample_id, vel)
  if event_type == "on" then
    note_on(sample_id, vel)
  else
    note_off(sample_id)
  end
end

local function set_sample_id(id)
  current_sample_id = id
  while current_sample_id >= num_samples do current_sample_id = current_sample_id - num_samples end
  while current_sample_id < 0 do current_sample_id = current_sample_id + num_samples end
end

function note_on(sample_id, vel)
  if timber.samples_meta[sample_id].num_frames > 0 then
    --print("note_on", sample_id)
    vel = vel or 1
    engine.noteOn(sample_id, MusicUtil.note_num_to_freq(60), vel, sample_id)
    sample_status[sample_id] = STATUS.PLAYING

  end
end

function note_off(sample_id)
  --print("note_off", sample_id)
  engine.noteOff(sample_id)

end

local function set_pressure_voice(voice_id, pressure)
  engine.pressureVoice(voice_id, pressure)
end

local function set_pressure_sample(sample_id, pressure)
  engine.pressureSample(sample_id, pressure)
end

local function set_pressure_all(pressure)
  engine.pressureAll(pressure)
end

local function set_pitch_bend_voice(voice_id, bend_st)
  engine.pitchBendVoice(voice_id, MusicUtil.interval_to_ratio(bend_st))
end

local function set_pitch_bend_sample(sample_id, bend_st)
  engine.pitchBendSample(sample_id, MusicUtil.interval_to_ratio(bend_st))
end

local function set_pitch_bend_all(bend_st)
  engine.pitchBendAll(MusicUtil.interval_to_ratio(bend_st))
end

local function key_down(sample_id, vel)
  if params:get("launch_mode_" .. sample_id) == 1 then
    queue_note_event("on", sample_id, vel)
  else
    if (sample_status[sample_id] ~= STATUS.PLAYING and sample_status[sample_id] ~= STATUS.STARTING) or sample_status[sample_id] == STATUS.STOPPING then
      queue_note_event("on", sample_id, vel)
    else
      queue_note_event("off", sample_id)
    end
  end
end

local function key_up(sample_id)
  if params:get("launch_mode_" .. sample_id) == 1 and params:get("play_mode_" .. sample_id) ~= 4 then
    queue_note_event("off", sample_id)
  end
end

-- timber MIDI input
local function midi_event(device_id, data)
  
  local msg = midi.to_msg(data)
  local channel_param = params:get("midi_in_channel")
  
  -- MIDI In
  if device_id == params:get("midi_in_device") then
    if channel_param == 1 or (channel_param > 1 and msg.ch == channel_param - 1) then
      
      -- Note off
      if msg.type == "note_off" then
        key_up(msg.note)
      -- Note on
      elseif msg.type == "note_on" then
        key_down(msg.note, msg.vel / 127)
        
      -- Key pressure
      elseif msg.type == "key_pressure" then
        set_pressure_voice(msg.note, msg.val / 127)
        
      -- Channel pressure
      elseif msg.type == "channel_pressure" then
        set_pressure_all(msg.val / 127)
        
      -- Pitch bend
      elseif msg.type == "pitchbend" then
        local bend_st = (util.round(msg.val / 2)) / 8192 * 2 -1 -- Convert to -1 to 1
        local bend_range = params:get("bend_range")
        set_pitch_bend_all(bend_st * bend_range)
      end
    end
  end
end

local function reconnect_midi_ins()
  midi_in_device.event = nil
  midi_clock_in_device.event = nil
  midi_in_device = midi.connect(params:get("midi_in_device"))
  midi_clock_in_device = midi.connect(params:get("midi_clock_in_device"))
  midi_in_device.event = function(data) midi_event(params:get("midi_in_device"), data) end
  midi_clock_in_device.event = function(data) midi_event(params:get("midi_clock_in_device"), data) end
end

-- END TIMBER sTUFF
-------------------------

-- 1=lvl, 2=rate

local function position_callback(pos)
  print(pos)
end

local v = {
  {1,1,1,1},
  {1,1,1,1},
  {17000,17000,17000,17000}
}

function init()
  midi_in_device = midi.connect(1)
  midi_in_device.event = function(data) midi_event(1, data) end
  
  midi_clock_in_device = midi.connect(1)
  midi_clock_in_device.event = function(data) midi_event(1, data) end
  clock.run(tempo, temp0)
  
  audio.level_cut(1)
  audio.level_adc_cut(1) -- record input
  audio.level_eng_cut(0) -- record engine
  for i=1,4 do
    if i<=2 then
        -- Voice 1,2 use the start of buffer 1,2
        softcut.buffer(i,i)
        softcut.position(i, 1)
        softcut.loop_start(i, 1)
        softcut.loop_end(i, 44)
        softcut.level_input_cut(i, i, 1.0) -- I don't understand channels. This may not be r ight.
      else
        -- Voice 3,4 use the end of buffer 1,2
        softcut.buffer(i,i-2)
        softcut.position(i, 45)
        softcut.loop_start(i, 45)
        softcut.loop_end(i, 91)
        softcut.level_input_cut(i-2, i, 1.0) -- I don't understand channels. This may not be r ight.
    end
    softcut.level(i,0)
    softcut.level_slew_time(i,0.01)
    softcut.post_filter_lp(i,1.0)
    softcut.post_filter_dry(i,0.0)
    softcut.post_filter_fc(i,17000)
    softcut.post_filter_rq(i,10)
    softcut.pan(i, 0)
    softcut.play(i, 1)
    softcut.rate(i, 1)
    softcut.rate_slew_time(i,0.1)
    softcut.loop(i, 1)
    softcut.fade_time(i, 0.1)
    softcut.rec(i, 1)
    softcut.rec_level(i, 0)
    softcut.pre_level(i, 0.5)
    softcut.enable(i, 1)
    softcut.filter_dry(i, 1);
  end
  add_params()
end


function tempo(v)
  while true do
    clock.sync(4/4)
    
    if recOn then
        rec(s1)
        recOn = false
      else if odOn then
        ovrdub(s1)
        odOn = false
        else if recOff or odOff then
          play(s1)
          recOff = false
          odOff = false
        end
      end
    end
    
    if daBeat == 4 then
      daBeat = 1
      else
        daBeat = daBeat + 1
    end
    redraw()
  end
end


function rec(i)
  start_time[i] = util.time()
  if s1 <= 2 then
    -- if voice 1,2 clear correct section of buffers
    softcut.buffer_clear_region_channel(i,0,44) -- I don't understand channels. This may not be r ight.
    softcut.position(i, 1)
    softcut.loop_end(i, 44)
    print("clear "..i)
  else
    -- if voice 3,4 clear correct section of buffers
    softcut.buffer_clear_region_channel(i-2,45,91) -- I don't understand channels. This may not be r ight.
    softcut.position(i, 45)
    softcut.loop_end(i, 91)
     print("clear "..i)
  end
  softcut.level(i,0)
  softcut.rec_level(i, 1)
  softcut.pre_level(i, 0)
  state[i] = "rec"
  print("recording "..i)
end

function ovrdub(i)
  start_time[i] = util.time()
  if s1 <= 2 then
    -- if voice 1,2 clear correct section of buffers
    softcut.position(i, 1)
    softcut.loop_end(i, 44)
    print("overdub "..i)
  else
    -- if voice 3,4 clear correct section of buffers
    softcut.position(i, 45)
    softcut.loop_end(i, 91)
     print("overdub "..i)
  end
  softcut.level(i,1)
  softcut.rec_level(i, 1)
  softcut.pre_level(i, .5)
  state[i] = "rec"
  print("dubbing "..i)
end

function play(i)
  loop_len[i] = util.time() - start_time[i]
  print(loop_len[i])
  softcut.level(i,1)
  softcut.rec_level(i, 0)
  softcut.pre_level(i, 1)
  if i <=2 then
    -- Voice 1,2 play correct portion of buffer
    softcut.position(i, 1)
    softcut.loop_end(i, loop_len[i] + 1)
    print("play "..i)
  else
    -- Voice 3,4 play correct portion of buffer
    softcut.position(i, 45)
    softcut.loop_end(i, loop_len[i] + 45)
    print("play "..i.." loop end "..loop_len[i])
  end
  state[i] = "play"
end

function key(n,z)
  
  if n==1 and z==1 then
    modd = true
    print(modd)
  else
    modd = false
  end

  if n==2 and z==1 and state[s1]~="rec" then
    odOn = true
    --ovrdub(s1)
  elseif n==2 and z==1 and state[s1]=="rec" then
    odOff = true
    --play(s1)
  end
  
  if n==3 and z==1 and not modd and state[s1]~="rec" then
    recOn = true
    --rec(s1)
  elseif n==3 and z==1 and state[s1]=="rec" then
    recOff = true 
    --play(s1)
  end
  redraw()
end

function enc(n,z)
  if n==1 then 
    -- select track.
    s1 = s1 + z
    s1 = util.clamp(s1,1,4)
    
  elseif n==2 then
    -- select feature on track.
    s2 = s2 + z
    s2 = util.clamp(s2,1,3)
  elseif n == 3 and modd then
    temp0 = temp0 + z
    params:set("clock_tempo",temp0)
    print('set tempo internal if its not changing')
  elseif n==3 and not modd then
    -- change selected feature.
    if s2 == 1 then
      -- change volume for selected voice.
      v[s2][s1] = util.clamp(v[s2][s1]+ (z*.1),0,10)
      softcut.level(s1, v[s2][s1])
      print(v[s2][s1])
    elseif s2 == 2 then
      -- change rate for selected voice
      v[s2][s1] = util.clamp(v[s2][s1]+(z*.5),-2,2)
      softcut.rate(s1, v[s2][s1])
    elseif s2 == 3 then
      if v[s2][s1] >= 500 then 
        v[s2][s1] = v[s2][s1] + (z*150)
      else
        v[s2][s1] = v[s2][s1] + (z*10)
      end
      v[s2][s1] = util.clamp(v[s2][s1],0,25000)
      softcut.post_filter_fc(s1,v[s2][s1])
    end
  end
  redraw()
end

------ dRawiNG stUFF ---------
-- Images
local t1 = {
  {1,1,1,1,1},
  {1,0,0,0,1},
  {1,0,0,0,1},
  {1,0,0,0,1},
  {1,1,1,1,1}
}
local t2 = {
  {1,1,1,1,1},
  {1,0,0,0,1},
  {1,0,0,0,1},
  {1,0,0,1,1},
  {1,1,1,1,0}
}
local t3 = {
  {1,1,1,1,1},
  {1,0,0,0,1},
  {1,0,1,0,1},
  {1,0,0,0,1},
  {1,1,1,1,1}
}
local t4 = {
  {1,1,1,1,1},
  {1,0,0,0,1},
  {1,0,0,0,1},
  {1,0,0,0,1},
  {0,1,1,1,1}
}

-- Track X offsets
local toffsetx = 20
local toffsety = 10
local topoffset = 10

function redraw()
  screen.clear()
  
  -- the four tracks
  for x in ipairs(t1) do
    for y in ipairs(t1) do 
      screen.level(s1 == 1 and 15 or 2)
      if t1[x][y] == 1 then
        if state[1] == 'rec' then 
          screen.pixel(x+10+toffsetx,y+5+math.random(18))
        end
        screen.pixel(x+10+toffsetx,y+15)
        screen.fill()
      end
      screen.level(s1 == 2 and 15 or 2)
      if t2[x][y] == 1 then
        if state[2] == 'rec' then 
          screen.pixel(x+10+(toffsetx*2),y+5+math.random(18))
        end
        screen.pixel(x+10+(toffsetx*2),y+15)
        screen.fill()
      end
      screen.level(s1 == 3 and 15 or 2)
      if t3[x][y] == 1 then
        if state[3] == 'rec' then 
          screen.pixel(x+10+(toffsetx*3),y+5+math.random(18))
        end
        screen.pixel(x+10+(toffsetx*3),y+15)
        screen.fill()
      end
      screen.level(s1 == 4 and 15 or 2)
      if t4[x][y] == 1 then
        if state[4] == 'rec' then 
          screen.pixel(x+10+(toffsetx*4),y+5+math.random(18))
        end
        screen.pixel(x+10+(toffsetx*4),y+15)
        screen.fill()
      end
    end
  end
  
  -- level
  screen.level(s2 == 1 and s1 == 1 and 15 or 2)
  lvl = util.linlin(0,10,1,5,v[1][1])
  screen.move(10+toffsetx+1,23)
  screen.line(lvl+10+toffsetx+1,23)
  screen.stroke()
  
  screen.level(s2 == 1 and s1 == 2 and 15 or 2)
  lvl = util.linlin(0,10,1,5,v[1][2])
  screen.move(10+(toffsetx*2)+1,23)
  screen.line(lvl+10+(toffsetx*2)+1,23)
  screen.stroke()
  
  screen.level(s2 == 1 and s1 == 3 and 15 or 2)
  lvl = util.linlin(0,10,1,5,v[1][3])
  screen.move(10+(toffsetx*3)+1,23)
  screen.line(lvl+10+(toffsetx*3)+1,23)
  screen.stroke()
  
  screen.level(s2 == 1 and s1 == 4 and 15 or 2)
  lvl = util.linlin(0,10,1,5,v[1][4])
  screen.move(10+(toffsetx*4)+1,23)
  screen.line(lvl+10+(toffsetx*4)+1,23)
  screen.stroke()
  
  -- rate
  screen.level(s2 == 2 and s1 == 1 and 15 or 2)
  lvl = util.linlin(-2,2,1,5,v[2][1])
  screen.move(31,25)
  screen.line(lvl+31,25)
  screen.stroke()
  
  screen.level(s2 == 2 and s1 == 2 and 15 or 2)
  lvl = util.linlin(-2,2,1,5,v[2][2])
  screen.move(51,25)
  screen.line(lvl+51,25)
  screen.stroke()
  
  screen.level(s2 == 2 and s1 == 3 and 15 or 2)
  lvl = util.linlin(-2,2,1,5,v[2][3])
  screen.move(71,25)
  screen.line(lvl+71,25)
  screen.stroke()

  screen.level(s2 == 2 and s1 == 4 and 15 or 2)
  lvl = util.linlin(-2,2,1,5,v[2][4])
  screen.move(91,25)
  screen.line(lvl+91,25)
  screen.stroke()
  
  -- Lowpass
  screen.level(s2 == 3 and s1 == 1 and 15 or 2)
  lvl = util.linlin(0,17000,1,5,v[3][1])
  screen.move(31,27)
  screen.line(lvl+31,27)
  screen.stroke()
  
  screen.level(s2 == 3 and s1 == 2 and 15 or 2)
  lvl = util.linlin(0,17000,1,5,v[3][2])
  screen.move(51,27)
  screen.line(lvl+51,27)
  screen.stroke()
  
  screen.level(s2 == 3 and s1 == 3 and 15 or 2)
  lvl = util.linlin(0,17000,1,5,v[3][3])
  screen.move(71,27)
  screen.line(lvl+71,27)
  screen.stroke()

  screen.level(s2 == 3 and s1 == 4 and 15 or 2)
  lvl = util.linlin(0,17000,1,5,v[3][4])
  screen.move(91,27)
  screen.line(lvl+91,27)
  screen.stroke()
  
  -- words
  if s2 == 1 then 
    w1 = "LVL"
  elseif s2 == 2 then
    w1 = "RTE"
  elseif s2 == 3 then
    w1 = "FLT"
  end
  
  screen.level(2)
  screen.move(31,50)
  screen.font_size(8)
  screen.font_face(1)
  screen.text(w1.." "..v[s2][s1])
  
  screen.move(76,49)
  screen.level(15)
  if daBeat == 1 then
    screen.text("* - - -")
    else if daBeat == 2 then
      screen.text("- * - -")
      else if daBeat == 3 then
        screen.text("- - * -") 
        else
          screen.text("- - - *")
      end
    end
  end
  screen.move(83,56)
  screen.level(15)
  screen.text(math.floor(clock.get_tempo()))
    
  screen.update()
  
end
