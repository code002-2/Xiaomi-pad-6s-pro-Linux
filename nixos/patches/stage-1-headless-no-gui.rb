# ---
# Module: Headless No GUI
# Description: Mobile NixOS stage-1 patch to disable GUI
# Scope: Patch
# ---

module ShengHeadlessStage1
  def self.enabled?()
    (Configuration["gui"] && Configuration["gui"]["enable"] == false) ||
      (Configuration["splash"] && Configuration["splash"]["disabled"])
  end
end

class Tasks::Splash
  def initialize()
    add_dependency(:Target, :Graphics) unless ShengHeadlessStage1.enabled?
    add_dependency(:Task, Tasks::ProgressSocket.instance)
  end

  def run()
    return if ShengHeadlessStage1.enabled?
    args = []
    if LOG_LEVEL == Logger::DEBUG
      args << "--verbose"
    end

    if System.cmdline().grep("mobile-nixos.kexec=yes").any?
      args << "--skip-fadein"
    end

    wait_for_input_devices

    begin
      $logger.info "Starting splash..."
      @pid = System.spawn(LOADER, "/applets/boot-splash.mrb", *args)
    rescue System::CommandError
    end
  end

  def quit(reason, sticky: nil)
    return if ShengHeadlessStage1.enabled?
    return if @pid.nil?
    count = 0
    Progress.update({progress: 100, label: reason})
    Progress.update({command: {name: "quit"}, sticky: sticky})
    loop do
      Progress.send_state()
      break if Process.wait(@pid, Process::WNOHANG)
      sleep(0.1)
      count += 1
      if count > 60
        $logger.fatal("Splash applet would not quit by itself...")
        kill
        break
      end
    end
    @pid = nil
  end
end

class Tasks::Graphics
  def initialize()
    unless ShengHeadlessStage1.enabled?
      add_dependency(
        :Any,
        Dependencies::Task.new(FBDev.instance),
        Dependencies::Task.new(DRM.instance),
      )
    end

    Targets[:Graphics].add_dependency(:Task, self)
  end
end

class Tasks::Graphics::FBDev
  def initialize()
    return if ShengHeadlessStage1.enabled?
    add_dependency(
      :Files,
      "/sys/class/graphics/fb0",
    )
    add_dependency(:Mount, "/dev")
  end
end

class Tasks::Graphics::DRM
  def initialize()
    return if ShengHeadlessStage1.enabled?
    add_dependency(
      :Files,
      "/dev/dri/card0",
    )
    add_dependency(:Mount, "/dev")
  end
end

class Tasks::SwitchRoot
  def selected_generation()
    return @selected_generation if @selected_generation

    if Hal::Recovery.wants_recovery? && !ShengHeadlessStage1.enabled?
      Tasks::Splash.instance.quit("Continuing to recovery menu")
      @selected_generation = choose_generation()
    else
      if Hal::Recovery.wants_recovery?
        $logger.info("Headless stage-1: skipping recovery generation menu.")
      end

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
