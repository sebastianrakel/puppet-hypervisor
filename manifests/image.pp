# @summary
#   Downloads and manages a disk image for use with KVM/QEMU virtual machines.
#
# @param download_url
#   URL from which the image is fetched. Passed as the `source` of a `file`
#   resource, so any protocol supported by Puppet's file server is accepted
#   (e.g. `http://`, `https://`, `puppet://`).
#
# @param image_name
#   Filename under which the image is stored in `/var/lib/libvirt/images`.
#   Defaults to the resource title.
#
# @param sha256_checksum
#   Expected SHA-256 checksum of the downloaded file. When provided, Puppet
#   verifies the file integrity after each download. Omit to skip checksum
#   validation.
define hypervisor::image (
  String[1] $download_url,
  String[1] $image_name = $name,
  Optional[String] $sha256_checksum = undef,
) {
  file { "/var/lib/libvirt/images/${image_name}":
    ensure         => 'file',
    source         => $download_url,
    checksum       => 'sha256',
    checksum_value => $sha256_checksum,
  }
}
