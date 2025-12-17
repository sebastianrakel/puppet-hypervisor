define hypervisor::image(
  String[1] $image_name = $name,
  String[1] $download_url, 
  Optional[String] $sha256_checksum = undef,
) {
  file { "/var/lib/libvirt/images/${image_name}":
    ensure         => 'file',
    source         => $download_url,
    checksum       => 'sha256',
    checksum_value => $sha256_checksum,
  }
}
