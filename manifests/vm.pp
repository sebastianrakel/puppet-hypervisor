# @summary
#   Defines and manages a KVM/QEMU virtual machine via libvirt.
#
# @param memory_mb
#   Amount of RAM to allocate to the VM, in mebibytes (MiB).
#
# @param disk_size
#   Size of the primary disk logical volume (e.g. '20G'). Passed directly to
#   the `logical_volume` resource.
#
# @param vm_name
#   Name of the VM as known to libvirt. Defaults to the resource title.
#
# @param disk_vg
#   LVM volume group in which the primary disk logical volume is created.
#
# @param autostart
#   Whether the VM should be configured to start automatically when the host
#   boots.
#
# @param image_directory
#   Directory used for ISO and cloud-init image files.
#
# @param iso
#   Filename of an ISO image (relative to `$image_directory`) to attach as a
#   SATA CD-ROM drive. Omit when no installation media is needed.
#
# @param base_image
#   Path to a qcow2 base image that will be converted and written to the
#   primary disk logical volume once, immediately after the volume is created.
#
# @param cloud_init_config
#   Hash of cloud-init user-data values. When provided, a cloud-init config
#   file and seed image are generated and attached as a SATA CD-ROM drive.
#
# @param networks
#   List of libvirt network names to attach to the VM as network interfaces.
#
# @param additional_disks
#   Hash of extra disks to create and attach. Each key becomes part of the
#   logical volume name (`<vm_name>_<key>`). Each value is a Hash with keys
#   `vg` (volume group) and `size` (disk size string).
#
# @param uefi
#   When true, configures the VM to boot via UEFI using OVMF firmware
#   (`OVMF_CODE_4M.ms.fd`) with a q35 machine type.
#
# @param cpu_model
#   Custom CPU model name to expose to the guest (e.g. `'Skylake-Client'`).
#   When set, the domain is configured with `mode=custom` and `match=exact`.
#   When `undef`, the hypervisor default CPU model is used.
#
# @param additional_isos
#   List of additional ISO filenames (relative to `$image_directory`) to
#   attach as extra SATA CD-ROM drives.
#
# @param cpu_count
#   Number of virtual CPUs to assign to the VM.
#
# @param ensure
#   Desired state of the VM domain:
#   - `running`  — domain is defined and active.
#   - `stopped`  — domain is defined but inactive.
#   - `present`  — domain is defined; active state is unmanaged.
#   - `absent`   — domain is removed.
#
# @param disk_bus
#   Bus type used for all disk devices (`virtio` or `sata`).
define hypervisor::vm (
  Integer $memory_mb,
  String $disk_size,
  String[1] $vm_name = $name,
  String $disk_vg = 'vg0',
  Boolean $autostart = true,
  String[1] $image_directory = '/var/lib/libvirt/images',
  Optional[String] $iso = undef,
  Optional[String] $base_image = undef,
  Optional[Hash] $cloud_init_config = undef,
  Array[String] $networks = ['default'],
  Hash[String, Hash] $additional_disks = {},
  Boolean $uefi = false,
  Optional[String] $cpu_model = undef,
  Array[String] $additional_isos = [],
  Integer $cpu_count = 1,
  Enum['running', 'present', 'stopped', 'absent'] $ensure = 'running',
  Enum['virtio', 'sata'] $disk_bus = 'virtio',
) {
  $disk_name = "${vm_name}_disk"

  logical_volume { $disk_name:
    ensure       => present,
    volume_group => $disk_vg,
    size         => $disk_size,
  }

  if ($base_image) {
    exec { "convert to physical disk ${vm_name}":
      command     => "qemu-img convert -f qcow2 -O raw ${base_image} /dev/${disk_vg}/${disk_name}",
      cwd         => $image_directory,
      path        => '/usr/bin',
      refreshonly => true,
      subscribe   => Logical_Volume[$disk_name],
    }
  }

  if ($iso) {
    $iso_disk = [{
      'type'   => 'file',
      'device' => 'cdrom',
      'bus'    => 'sata',
      'source' => {
        'file' => "${image_directory}/${iso}",
      },
      'driver' => {
        'name'  => 'qemu',
        'type'  => 'raw',
      },
    }]
  } else {
    $iso_disk = []
  }

  $final_additional_isos = $additional_isos.map |String $additonal_iso| {
    {
      'type'   => 'file',
      'device' => 'cdrom',
      'bus'    => 'sata',
      'source' => {
        'file' => "${image_directory}/${additonal_iso}",
      },
      'driver' => {
        'name'  => 'qemu',
        'type'  => 'raw',
      },
    }
  }

  if ($cloud_init_config) {
    $cloud_init_image = "${image_directory}/${vm_name}-cloud-init.img"

    file { "${image_directory}/${vm_name}_cloud_init.cfg":
      ensure  => 'file',
      content => epp("${module_name}/cloud_init.cfg.epp", {
        data => $cloud_init_config
      }),
    }

    exec { "create cloud_init.cfg ${vm_name}":
      command => "cloud-localds ${vm_name}-cloud-init.img ${vm_name}_cloud_init.cfg",
      cwd     => $image_directory,
      path    => '/usr/bin',
      creates => $cloud_init_image,
    }

    $cloud_init_disk = [{
      'type'   => 'file',
      'device' => 'cdrom',
      'bus'    => 'sata',
      'source' => {
        'file' => $cloud_init_image,
      },
      'driver' => {
        'name'  => 'qemu',
        'type'  => 'raw',
      },
    }]
  } else {
    $cloud_init_disk = []
  }

  if ($additional_disks.length > 0) {
    $additional_disks.each |String $disk_name, Hash $options| {
      $vg = $options['vg']
      $full_disk_name = "${vm_name}_${disk_name}"

      logical_volume { $full_disk_name:
        ensure       => present,
        volume_group => $vg,
        size         => $options['size'],
      }
    }

    $libvirt_additional_disks = $additional_disks.map |String $disk_name, Hash $options| {
      {
        'type'   => 'block',
        'device' => 'disk',
        'bus'    => $disk_bus,
        'source' => {
          'dev' => "/dev/${options['vg']}/${vm_name}_${disk_name}",
        },
        'driver' => {
          'name' => 'qemu',
          'type' => 'raw',
        },
      }
    }
  } else {
    $libvirt_additional_disks = []
  }

  $vm_networks = $networks.map |String $network| {
    { 'network' => $network }
  }

  $domconfig = {
    vcpu => {
      values => $cpu_count,
      attrs => {
        placement => 'static',
      },
    },
    memory => {
      values => $memory_mb,
      attrs  => {
        unit => 'MiB',
      },
    },
  }

  if ($uefi) {
    $domconfig_uefi = {
      os => {
        values   => {
          type     => {
            attrs => {
              arch => 'x86_64',
              machine => 'q35',
            },
            values => 'hvm',
          },
          loader   => {
            attrs  => {
              readonly => 'yes',
              type     => 'pflash',
            },
            values => '/usr/share/OVMF/OVMF_CODE_4M.ms.fd',
          },
        },
      },
    }
  } else {
    $domconfig_uefi = {}
  }

  if ($cpu_model != undef) {
    $domconfig_cpu = {
      cpu => {
        attrs => {
          mode  => 'custom',
          match => 'exact',
          check => 'partial',
        },
        values   => {
          model => {
            attrs => {
              fallback  => 'allow',
            },
            values => $cpu_model,
          },
        },
      },
    }
  } else {
    $domconfig_cpu = {}
  }

  $active_state = $ensure ? {
    'running' => true,
    'stopped' => false,
    'present' => undef,
    default   => undef,
  }

  libvirt::domain { $vm_name:
    boot       => 'hd',
    domconf    => $domconfig + $domconfig_uefi + $domconfig_cpu,
    interfaces => [] + $vm_networks,
    autostart  => $autostart,
    active     => $active_state,
    replace    => true,
    disks      => [
      {
        'type'   => 'block',
        'device' => 'disk',
        'bus'    => $disk_bus,
        'source' => {
          'dev' => "/dev/${disk_vg}/${disk_name}",
        },
        'driver' => {
          'name' => 'qemu',
          'type' => 'raw',
        },
      },
    ] + $iso_disk
    + $cloud_init_disk
    + $libvirt_additional_disks
    + $final_additional_isos,
  }
}
