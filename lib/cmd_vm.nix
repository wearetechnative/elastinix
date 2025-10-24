{ inputs, ... } :
  { nixpkgs,
    runSystem,
    machineConfig ? {},
    targetSystem ? "x86_64-linux",
    tfBinOverride ? "",
    terraformBinConf ? { distribution = "terraform"; version = "1-5-3"; },
    cmd ? "apply",
    varsfile ? "" ,
    rootAuthorizedKeys ? [] } :
let
  pkgsRunSys = import nixpkgs { system = runSystem; };
  qcowImage = (import ./os_config_vm.nix { inherit inputs; }) { inherit nixpkgs targetSystem rootAuthorizedKeys machineConfig varsfile;};
  mem = "4G";
  threads = 4;
  cores = 2;
  sockets = 1;
  sshListenAddr = "127.0.0.1";
  sshPort = 2222;
in

pkgsRunSys.writeShellScriptBin "runvm" ''

      args=(
      -enable-kvm -m "${mem}"
      #-cpu Penryn,kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,"$MY_OPTIONS"
      #-machine q35
      #-usb -device usb-kbd -device usb-tablet -device usb-tablet
      -smp "${toString threads}",cores="${toString cores}",sockets="${toString sockets}"
      -device usb-ehci,id=ehci
      #-smbios type=2
      #-device ich9-intel-hda -device hda-duplex
      #-drive id=drive1,if=virtio,file="nixos-image.qcow2",format=qcow2
      -netdev user,id=net0,hostfwd=tcp:${sshListenAddr}:${toString sshPort}-:22 -device virtio-net-pci,netdev=net0,id=net0,mac=52:54:00:c9:18:27

      -drive cache=writeback,file=nixos-image.qcow2,id=drive1,if=none,index=1,werror=report
      #-device virtio-blk-pci,bootindex=1,drive=drive1 \
      #   -nographic

      #-monitor stdio
      #-device virtio-vga
      "$@"
      )

  if [ ! -f nixos-image.qcow2 ]; then
    echo 'The disk image nixos.qcow2 was not found, creating it:'
    ${pkgsRunSys.qemu_kvm}/bin/qemu-img create -b nixos-image.qcow2 -F qcow2 -f qcow2 ${qcowImage}/nixos.qcow2
  fi

  # Sometimes plugins like JACK will not be compatible with QEMU from this
  # flake, so unset LD_LIBRARY_PATH
  set -x
  unset LD_LIBRARY_PATH
  ${pkgsRunSys.qemu_kvm}/bin/qemu-system-x86_64 "''${args[@]}"


``

