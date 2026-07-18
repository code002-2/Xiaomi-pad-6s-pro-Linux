# ---
# Module: Headless Generation Menu
# Description: Mobile NixOS stage-1 headless boot menu implementation
# Scope: Patch
# ---

module ShengHeadlessGenerationMenu
  extend self

  VOLUME_UP = [:KEY_VOLUMEUP, :KEY_UP]
  VOLUME_DOWN = [:KEY_VOLUMEDOWN, :KEY_DOWN]
  CONFIRM = [:KEY_POWER, :KEY_ENTER, :KEY_KPENTER]
  REQUEST_PATH = "/mnt/var/lib/sheng-boot-menu/requested"
  MENU_CONSOLE_PATH = "/dev/tty2"
  FALLBACK_CONSOLE_PATH = "/dev/tty0"
  FB_PATH = "/dev/fb0"
  FB_SYSFS = "/sys/class/graphics/fb0"
  MENU_X = 96
  MENU_Y = 96
  FONT_SCALE = 4
  ROW_HEIGHT = 40
  TITLE_HEIGHT = 40
  HEADER_GAP = 38
  FOOTER_GAP = 44
  BG = [0, 0, 0]
  SELECT_BG = [0, 48, 0]
  TITLE_FG = [0, 220, 220]
  SELECT_FG = [0, 255, 0]
  NORMAL_FG = [220, 220, 220]
  STATUS_FG = [210, 210, 210]
  EV_KEY = 1
  KEY_VOLUMEUP = 115
  KEY_VOLUMEDOWN = 114
  KEY_POWER = 116
  KEY_UP = 103
  KEY_DOWN = 108
  KEY_ENTER = 28
  KEY_KPENTER = 96
  INPUT_EVENT_SIZE = 24
  INPUT_SCAN_INTERVAL = 0.25
  INPUT_ACTION_CODES = {
    up: [KEY_VOLUMEUP, KEY_UP],
    down: [KEY_VOLUMEDOWN, KEY_DOWN],
    confirm: [KEY_POWER, KEY_ENTER, KEY_KPENTER]
  }

  FONT = {
    " " => ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
    "!" => ["00100", "00100", "00100", "00100", "00100", "00000", "00100"],
    "#" => ["01010", "11111", "01010", "01010", "11111", "01010", "01010"],
    "(" => ["00010", "00100", "01000", "01000", "01000", "00100", "00010"],
    ")" => ["01000", "00100", "00010", "00010", "00010", "00100", "01000"],
    "+" => ["00000", "00100", "00100", "11111", "00100", "00100", "00000"],
    "-" => ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    "." => ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
    "/" => ["00001", "00010", "00100", "01000", "10000", "00000", "00000"],
    "0" => ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1" => ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2" => ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3" => ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4" => ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5" => ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
    "6" => ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7" => ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8" => ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9" => ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    ":" => ["00000", "01100", "01100", "00000", "01100", "01100", "00000"],
    ">" => ["10000", "01000", "00100", "00010", "00100", "01000", "10000"],
    "?" => ["01110", "10001", "00001", "00010", "00100", "00000", "00100"],
    "[" => ["01110", "01000", "01000", "01000", "01000", "01000", "01110"],
    "]" => ["01110", "00010", "00010", "00010", "00010", "00010", "01110"],
    "_" => ["00000", "00000", "00000", "00000", "00000", "00000", "11111"],
    "A" => ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B" => ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C" => ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
    "D" => ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E" => ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F" => ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G" => ["01110", "10001", "10000", "10111", "10001", "10001", "01110"],
    "H" => ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I" => ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
    "J" => ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
    "K" => ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L" => ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M" => ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N" => ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O" => ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P" => ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "Q" => ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "R" => ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S" => ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T" => ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U" => ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V" => ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "W" => ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
    "X" => ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "Y" => ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "Z" => ["11111", "00001", "00010", "00100", "01000", "10000", "11111"]
  }

  def config()
    Configuration["sheng_generation_menu"] || {}
  end

  def enabled?()
    config()["enable"] == true
  end

  def timeout()
    (config()["timeout"] || 30).to_i
  end

  def requested?()
    File.exist?(REQUEST_PATH)
  end

  def consume_request()
    File.delete(REQUEST_PATH) if requested?()
  end

  def wait_for_release(keys)
    20.times do
      poll_input_action(0.01)
      break unless input_held?(keys)
    end
  end

  def input_devices()
    @input_devices ||= {}
  end

  def input_held()
    @input_held ||= {}
  end

  def input_open_flags()
    @input_open_flags ||= begin
      flags = File::RDONLY
      @input_nonblocking = File.const_defined?(:NONBLOCK)
      flags |= File::NONBLOCK if @input_nonblocking
      flags
    end
  end

  def key_codes(keys)
    keys.map do |key|
      case key
      when :KEY_VOLUMEUP
        KEY_VOLUMEUP
      when :KEY_VOLUMEDOWN
        KEY_VOLUMEDOWN
      when :KEY_POWER
        KEY_POWER
      when :KEY_UP
        KEY_UP
      when :KEY_DOWN
        KEY_DOWN
      when :KEY_ENTER
        KEY_ENTER
      when :KEY_KPENTER
        KEY_KPENTER
      else
        nil
      end
    end.compact
  end

  def remove_input_device(path)
    dev = input_devices.delete(path)
    input_held.delete(path)
    dev.close if dev && !dev.closed?
  rescue
  end

  def refresh_input_devices(force: false)
    now = Time.now.to_f
    if !force && @last_input_scan && now - @last_input_scan < INPUT_SCAN_INTERVAL
      return
    end

    @last_input_scan = now

    input_devices.keys.each do |path|
      remove_input_device(path) unless File.exist?(path)
    end

    Dir.glob("/dev/input/event*").sort.each do |path|
      next if input_devices.key?(path)

      begin
        input_devices[path] = File.open(path, input_open_flags())
        input_held[path] = {}
      rescue Errno::ENOENT, Errno::ENODEV, IOError, SystemCallError => error
        $logger.warn("Ignoring unavailable sheng generation menu input device #{path}: #{error}")
      end
    end
  end

  def input_action_for_code(code)
    return :up if INPUT_ACTION_CODES[:up].include?(code)
    return :down if INPUT_ACTION_CODES[:down].include?(code)
    return :confirm if INPUT_ACTION_CODES[:confirm].include?(code)

    nil
  end

  def unpack_input_event(data)
    return nil unless data && data.bytesize == INPUT_EVENT_SIZE

    bytes = data.bytes
    type = bytes[16] | (bytes[17] << 8)
    code = bytes[18] | (bytes[19] << 8)
    value = bytes[20] | (bytes[21] << 8) | (bytes[22] << 16) | (bytes[23] << 24)
    value -= 0x100000000 if value >= 0x80000000
    [type, code, value]
  rescue => error
    $logger.warn("Ignoring malformed sheng generation menu input event: #{error}")
    nil
  end

  def read_input_events(path, dev)
    action = nil
    reads = 0

    loop do
      data = dev.sysread(INPUT_EVENT_SIZE)
      break unless data && data.bytesize == INPUT_EVENT_SIZE

      event = unpack_input_event(data)
      next unless event

      type, code, value = event
      if type == EV_KEY
        input_held[path] ||= {}
        if value == 0
          input_held[path].delete(code)
        elsif value == 1 || value == 2
          input_held[path][code] = true
          action ||= input_action_for_code(code)
        end
      end

      reads += 1
      break if reads >= 32 || !@input_nonblocking
    end

    action
  rescue Errno::EAGAIN
    action
  rescue EOFError, Errno::ENOENT, Errno::ENODEV, IOError, SystemCallError => error
    $logger.warn("Removing stale sheng generation menu input device #{path}: #{error}")
    remove_input_device(path)
    action
  end

  def poll_input_action(timeout)
    refresh_input_devices()

    readers = input_devices.values
    if readers.empty?
      sleep(timeout)
      return nil
    end

    ready = IO.select(readers, nil, nil, timeout)
    return nil unless ready

    ready[0].each do |dev|
      path = input_devices.key(dev)
      next unless path

      action = read_input_events(path, dev)
      return action if action
    end

    nil
  rescue => error
    $logger.warn("Ignoring sheng generation menu input polling failure: #{error}")
    sleep(timeout)
    nil
  end

  def input_held?(keys)
    codes = key_codes(keys)
    input_held.values.any? do |states|
      codes.any? { |code| states[code] }
    end
  end

  def console_path()
    @console_path || FALLBACK_CONSOLE_PATH
  end

  def console()
    @console ||= begin
      File.open(console_path(), "w")
    rescue
      $stderr
    end
  end

  def activate_console()
    System.run("chvt", "2")
    @console_path = MENU_CONSOLE_PATH
  rescue System::CommandError => error
    @console_path = FALLBACK_CONSOLE_PATH
    $logger.warn("Could not switch to sheng generation menu console: #{error}")
  end

  def set_console_echo(enabled)
    if enabled
      System.run("stty", "-F", console_path(), "sane")
    else
      System.run(
        "stty",
        "-F",
        console_path(),
        "raw",
        "-echo",
        "-echoe",
        "-echok",
        "-echoctl",
        "-echoke",
        "min",
        "0",
        "time",
        "0"
      )
    end
  rescue System::CommandError => error
    $logger.warn("Could not update sheng generation menu console echo: #{error}")
  end

  def set_console_keyboard(enabled)
    mode = enabled ? "-u" : "-s"
    System.run("kbd_mode", "-f", mode, "-C", console_path())
  rescue System::CommandError => error
    $logger.warn("Could not update sheng generation menu keyboard mode: #{error}")
  end

  def suppress_console_logs()
    @previous_printk = File.read("/proc/sys/kernel/printk")
    File.write("/proc/sys/kernel/printk", "1\n")
  rescue => error
    $logger.warn("Could not suppress kernel logs during sheng generation menu: #{error}")
  end

  def restore_console_logs()
    File.write("/proc/sys/kernel/printk", @previous_printk) if @previous_printk
  rescue => error
    $logger.warn("Could not restore kernel console log level: #{error}")
  end

  def framebuffer()
    @framebuffer ||= File.open(FB_PATH, "r+b")
  end

  def read_fb_integer(name, fallback)
    path = "#{FB_SYSFS}/#{name}"
    return fallback unless File.exist?(path)

    File.read(path).strip.to_i
  rescue
    fallback
  end

  def framebuffer_info()
    return if @fb_ready

    size = File.read("#{FB_SYSFS}/virtual_size").strip.split(",").map { |part| part.to_i }
    @fb_width = size[0]
    @fb_height = size[1]
    @fb_bpp = read_fb_integer("bits_per_pixel", 32)
    @fb_bytes = [@fb_bpp / 8, 2].max
    @fb_stride = read_fb_integer("stride", @fb_width * @fb_bytes)
    @fb_stride = @fb_width * @fb_bytes if @fb_stride <= 0
    @fb_ready = true
  end

  def pixel(color)
    r, g, b = color
    case @fb_bpp
    when 16
      value = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
      [value].pack("v")
    when 24
      [b, g, r].pack("C3")
    else
      [b, g, r, 0].pack("C4")
    end
  end

  def clamp(value, min, max)
    return min if value < min
    return max if value > max

    value
  end

  def draw_rect(x, y, width, height, color)
    framebuffer_info()
    return if width <= 0 || height <= 0

    x = clamp(x, 0, @fb_width)
    y = clamp(y, 0, @fb_height)
    width = clamp(width, 0, @fb_width - x)
    height = clamp(height, 0, @fb_height - y)
    return if width <= 0 || height <= 0

    row = pixel(color) * width
    current_y = y
    while current_y < y + height
      framebuffer.sysseek(current_y * @fb_stride + x * @fb_bytes, IO::SEEK_SET)
      framebuffer.syswrite(row)
      current_y += 1
    end
  end

  def glyph(char)
    FONT[char.upcase] || FONT["?"]
  end

  def text_pixels(text, width, height, fg, bg)
    framebuffer_info()
    fg_pixel = pixel(fg)
    bg_pixel = pixel(bg)
    scale = FONT_SCALE
    lines = Array.new(height) { bg_pixel * width }
    chars = text.to_s.upcase.each_char.to_a
    max_chars = [width / (6 * scale), 0].max
    chars = chars[0, max_chars]

    7.times do |glyph_y|
      scale.times do |sy|
        dst_y = glyph_y * scale + sy
        next if dst_y >= height

        row = lines[dst_y].dup
        char_x = 0
        chars.each do |char|
          bits = glyph(char)[glyph_y]
          bits.each_char do |bit|
            pixel_data = bit == "1" ? fg_pixel : bg_pixel
            scale.times do |sx|
              dst_x = char_x + sx
              if dst_x < width
                row[dst_x * @fb_bytes, @fb_bytes] = pixel_data
              end
            end
            char_x += scale
          end
          char_x += scale
        end
        lines[dst_y] = row
      end
    end

    lines
  end

  def draw_text_box(x, y, width, height, text, fg, bg)
    framebuffer_info()
    return if width <= 0 || height <= 0

    x = clamp(x, 0, @fb_width)
    y = clamp(y, 0, @fb_height)
    width = clamp(width, 0, @fb_width - x)
    height = clamp(height, 0, @fb_height - y)
    return if width <= 0 || height <= 0

    lines = text_pixels(text, width, height, fg, bg)
    lines.each_with_index do |line, index|
      framebuffer.sysseek((y + index) * @fb_stride + x * @fb_bytes, IO::SEEK_SET)
      framebuffer.syswrite(line)
    end
  end

  def menu_width()
    framebuffer_info()
    clamp(@fb_width - MENU_X * 2, 320, 1900)
  end

  def menu_height(visible_count)
    TITLE_HEIGHT + HEADER_GAP + visible_count * ROW_HEIGHT + FOOTER_GAP + ROW_HEIGHT * 2
  end

  def max_visible_generations()
    framebuffer_info()
    available = @fb_height - MENU_Y - TITLE_HEIGHT - HEADER_GAP - FOOTER_GAP - ROW_HEIGHT * 3
    clamp(available / ROW_HEIGHT, 1, 24)
  end

  def visible_range(count, selected)
    visible = [count, max_visible_generations()].min
    start = 0

    if count > visible
      start = selected - visible / 2
      start = 0 if start < 0
      start = count - visible if start > count - visible
    end

    [start, start + visible]
  end

  def generation_row_text(label, index, selected)
    prefix = index == selected ? "> " : "  "
    "#{prefix}#{label}"
  end

  def status_line(remaining)
    if remaining
      "AUTOBOOT IN #{remaining} SECONDS. PRESS ANY KEY TO STOP."
    else
      "AUTOBOOT STOPPED. WAITING FOR SELECTION..."
    end
  end

  def draw_generation_row(labels, index, selected, start)
    row_y = MENU_Y + TITLE_HEIGHT + HEADER_GAP + (index - start) * ROW_HEIGHT
    bg = index == selected ? SELECT_BG : BG
    fg = index == selected ? SELECT_FG : NORMAL_FG
    draw_text_box(MENU_X, row_y - 6, menu_width(), ROW_HEIGHT, generation_row_text(labels[index], index, selected), fg, bg)
  end

  def render_framebuffer(generations, selected, previous_selected: nil, remaining: nil, previous_remaining: nil)
    framebuffer_info()
    labels = generations.empty? ? ["NixOS - Default"] : generations.map { |generation| generation.label() }
    start_index, end_index = visible_range(labels.length, selected)
    previous_start, previous_end =
      previous_selected.nil? ? [nil, nil] : visible_range(labels.length, previous_selected)
    full_redraw = previous_selected.nil? ||
      previous_start != start_index ||
      previous_end != end_index
    visible_count = end_index - start_index
    help_y = MENU_Y + TITLE_HEIGHT + HEADER_GAP + visible_count * ROW_HEIGHT + FOOTER_GAP
    status_y = help_y + ROW_HEIGHT

    if full_redraw
      draw_rect(0, 0, @fb_width, @fb_height, BG)
      draw_text_box(MENU_X, MENU_Y + 2, menu_width(), TITLE_HEIGHT, "NIXOS BOOT MENU", TITLE_FG, BG)
      index = start_index
      while index < end_index
        draw_generation_row(labels, index, selected, start_index)
        index += 1
      end
      draw_text_box(MENU_X, help_y - 6, menu_width(), ROW_HEIGHT, "[VOL/ARROW] NAVIGATE   [POWER/ENTER] SELECT", STATUS_FG, BG)
    elsif previous_selected != selected
      draw_generation_row(labels, previous_selected, selected, start_index) if previous_selected
      draw_generation_row(labels, selected, selected, start_index)
    end

    if full_redraw || previous_remaining != remaining
      draw_text_box(MENU_X, status_y - 6, menu_width(), ROW_HEIGHT, status_line(remaining), STATUS_FG, BG)
    end

    framebuffer.flush
  rescue => error
    $logger.warn("Could not render sheng generation menu framebuffer: #{error}")
  end

  def render(generations, selected, previous_selected: nil, remaining: nil, previous_remaining: nil)
    render_framebuffer(
      generations,
      selected,
      previous_selected: previous_selected,
      remaining: remaining,
      previous_remaining: previous_remaining
    )
  end

  def render_booting()
    framebuffer_info()
    draw_text_box(MENU_X, MENU_Y + 2, menu_width(), TITLE_HEIGHT, "BOOTING SELECTED GENERATION...", STATUS_FG, BG)
    framebuffer.flush
  rescue => error
    $logger.warn("Could not render sheng generation menu boot status: #{error}")
  end

  def choose(switch_root)
    generations = Tasks::SwitchRoot::NixOSGeneration.generations()
    selected = 0
    deadline = Time.now.to_i + timeout()
    countdown_active = true
    activate_console()
    set_console_echo(false)
    set_console_keyboard(false)
    suppress_console_logs()
    refresh_input_devices(force: true)
    input_held.clear
    wait_for_release(VOLUME_UP + VOLUME_DOWN + CONFIRM)
    last_selected = nil
    last_remaining = nil
    volume_up_was_pressed = false
    volume_down_was_pressed = false
    up_pressed_time = 0.0
    up_last_repeat = 0.0
    down_pressed_time = 0.0
    down_last_repeat = 0.0

    loop do
      remaining = countdown_active ? [deadline - Time.now.to_i, 0].max : nil
      needs_redraw = (selected != last_selected) || (remaining != last_remaining)

      if needs_redraw
        render(
          generations,
          selected,
          previous_selected: last_selected,
          remaining: remaining,
          previous_remaining: last_remaining
        )
        last_selected = selected
        last_remaining = remaining
      end

      input_action = poll_input_action(0.01)
      volume_up_pressed = input_held?(VOLUME_UP)
      volume_down_pressed = input_held?(VOLUME_DOWN)

      action_up = input_action == :up
      action_down = input_action == :down
      confirm_pressed = input_action == :confirm
      now_t = Time.now.to_f

      if volume_up_pressed
        if !volume_up_was_pressed
          up_pressed_time = now_t
          up_last_repeat = now_t
          action_up = true
        elsif now_t - up_pressed_time > 0.4 && now_t - up_last_repeat > 0.1
          action_up = true
          up_last_repeat = now_t
        end
      end

      if volume_down_pressed
        if !volume_down_was_pressed
          down_pressed_time = now_t
          down_last_repeat = now_t
          action_down = true
        elsif now_t - down_pressed_time > 0.4 && now_t - down_last_repeat > 0.1
          action_down = true
          down_last_repeat = now_t
        end
      end

      if action_up
        countdown_active = false
        menu_length = generations.empty? ? 1 : generations.length
        selected = (selected - 1) % menu_length
      elsif action_down
        countdown_active = false
        menu_length = generations.empty? ? 1 : generations.length
        selected = (selected + 1) % menu_length
      elsif confirm_pressed
        wait_for_release(CONFIRM)
        break
      elsif countdown_active && Time.now.to_i >= deadline
        break
      end

      volume_up_was_pressed = volume_up_pressed
      volume_down_was_pressed = volume_down_pressed
    end

    set_console_keyboard(true)
    restore_console_logs()
    set_console_echo(true)
    render_booting()

    if generations.empty?
      Tasks::SwitchRoot::NixOSGeneration.new(switch_root.default_selection_path())
    else
      generations[selected]
    end
  end
end

class Tasks::SwitchRoot
  def selected_generation()
    return @selected_generation if @selected_generation

    explicit_request = ShengHeadlessGenerationMenu.requested?()
    multiple_generations = NixOSGeneration.generations().length > 0
    wants_menu = explicit_request || multiple_generations

    if wants_menu &&
       ShengHeadlessStage1.enabled? &&
       ShengHeadlessGenerationMenu.enabled?
      ShengHeadlessGenerationMenu.consume_request()
      @selected_generation = ShengHeadlessGenerationMenu.choose(self)
    elsif wants_menu && !ShengHeadlessStage1.enabled?
      Tasks::Splash.instance.quit("Continuing to recovery menu")
      @selected_generation = choose_generation()
    else
      @selected_generation = NixOSGeneration.new(default_selection_path())
      if will_kexec?()
        Tasks::Splash.instance.quit("Rebooting in generation kernel", sticky: true)
      else
        Tasks::Splash.instance.quit("Continuing to stage-2")
      end
    end
    @selected_generation
  end
end
