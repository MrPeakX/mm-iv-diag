#!/usr/bin/env perl
# SPDX-License-Identifier: MIT
# tools/romtool.pl -- patch and verify the ROM image.
#
# Usage:
#   romtool.pl patch  IMAGE   check size and ident block, patch the CRCs
#   romtool.pl verify IMAGE   check size, ident block, CRCs and vectors
#   romtool.pl info   IMAGE   print the ident block (key=value lines)
#
# The ident block layout is read from include/ident.inc. All checksums
# are CRC-32 (IEEE 802.3, as zip), stored little endian, computed
# with the CRC area (the CRC field and the block CRC table) taken as
# zero: one over the whole image, and one per 4 KiB block (the ROM
# checks the blocks, diag/romchk.s).

use v5.40;
use Compress::Zlib ();
use File::Basename ();
use File::Spec ();

my $ROM_BASE = 0x8000;            # include/hw.inc: HW_ROM
my $ROM_SIZE = 0x8000;            # include/hw.inc: HW_ROM_SIZE
my $MAGIC    = 'MM-IV-DIAG';

my $ident_inc = File::Spec->catfile(File::Basename::dirname(__FILE__),
  File::Spec->updir(), 'include', 'ident.inc');

sub read_ident_layout() {
  open(my $fh, '<', $ident_inc) or die "$ident_inc: $!\n";
  my %layout;
  while (my $line = <$fh>) {
    if ($line =~ /^\s*(IDENT_\w+)\s*=\s*(\$[0-9A-Fa-f]+|\d+)/) {
      my ($name, $value) = ($1, $2);
      $layout{$name} = $value =~ s/^\$// ? hex($value) : $value;
    }
  }
  close($fh);
  for my $key (qw(BASE SIZE MAGIC MAGIC_LEN FORMAT VMAJOR VMINOR VPATCH
                  VSTRING VSTRING_LEN CONTACT CONTACT_LEN BUILD BUILD_LEN CRC CRC_LEN BCRC BCRC_LEN
                  BLOCKS BLOCK_SIZE FORMAT_VERSION)) {
    die "$ident_inc: IDENT_$key missing\n" unless exists $layout{"IDENT_$key"};
  }
  return \%layout;
}

sub read_image($file) {
  open(my $fh, '<:raw', $file) or die "$file: $!\n";
  local $/;
  my $data = <$fh>;
  close($fh);
  my $size = length($data);
  die "$file: size is $size bytes, expected $ROM_SIZE\n" if $size != $ROM_SIZE;
  return $data;
}

sub write_image($file, $data) {
  my $tmp = "$file.tmp";
  open(my $fh, '>:raw', $tmp) or die "$tmp: $!\n";
  print {$fh} $data;
  close($fh) or die "$tmp: $!\n";
  rename($tmp, $file) or die "$file: $!\n";
}

# Offset of an ident field inside the image.
sub field($l, $name) {
  return $l->{IDENT_BASE} - $ROM_BASE + $l->{"IDENT_$name"};
}

sub cstring($data, $l, $name) {
  my $s = substr($data, field($l, $name), $l->{"IDENT_${name}_LEN"});
  $s =~ s/\0.*\z//s;
  return $s;
}

# Image with the CRC area (CRC field and block CRC table) set to zero.
sub crc_input($data, $l) {
  my $copy = $data;
  my $start = field($l, 'CRC');
  my $end = field($l, 'BCRC') + $l->{IDENT_BCRC_LEN};
  substr($copy, $start, $end - $start) = "\0" x ($end - $start);
  return $copy;
}

# (whole-image CRC, [block CRCs])
sub compute_crcs($data, $l) {
  my $copy = crc_input($data, $l);
  my @blocks = map {
    Compress::Zlib::crc32(substr($copy, $_ * $l->{IDENT_BLOCK_SIZE}, $l->{IDENT_BLOCK_SIZE}))
  } 0 .. $l->{IDENT_BLOCKS} - 1;
  return (Compress::Zlib::crc32($copy), \@blocks);
}

sub stored_crcs($data, $l) {
  my @blocks = unpack('V*', substr($data, field($l, 'BCRC'), $l->{IDENT_BCRC_LEN}));
  return (unpack('V', substr($data, field($l, 'CRC'), 4)), \@blocks);
}

sub stored_crc($data, $l) { return (stored_crcs($data, $l))[0] }

sub check_ident($file, $data, $l) {
  my $magic = cstring($data, $l, 'MAGIC');
  die "$file: ident magic '$magic', expected '$MAGIC'\n" if $magic ne $MAGIC;
  my $format = ord(substr($data, field($l, 'FORMAT'), 1));
  die "$file: ident format $format, expected $l->{IDENT_FORMAT_VERSION}\n"
    if $format != $l->{IDENT_FORMAT_VERSION};
  my $contact = substr($data, field($l, 'CONTACT'), $l->{IDENT_CONTACT_LEN});
  die "$file: contact field not NUL terminated\n" unless $contact =~ /\0/;
  my $build = cstring($data, $l, 'BUILD');
  die "$file: bad build timestamp '$build'\n"
    unless $build =~ /\A\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\z/;
}

my $IDENT_END;                     # first address after the ident block (offset)

sub check_vectors($file, $data) {
  my %vec = (NMI => 0xFFFA, RESET => 0xFFFC, IRQ => 0xFFFE);
  for my $name (sort keys %vec) {
    my $target = unpack('v', substr($data, $vec{$name} - $ROM_BASE, 2));
    die sprintf("%s: %s vector \$%04X outside the ROM\n", $file, $name, $target)
      if $target < $ROM_BASE + $IDENT_END;
    die sprintf("%s: %s vector \$%04X points to erased ROM\n", $file, $name, $target)
      if substr($data, $target - $ROM_BASE, 1) eq "\xFF";
  }
}

sub info($data, $l) {
  my $off = field($l, 'VMAJOR');
  my ($major, $minor, $patch) = unpack('C3', substr($data, $off, 3));
  return (
    name      => cstring($data, $l, 'MAGIC'),
    version   => cstring($data, $l, 'VSTRING'),
    version_n => "$major.$minor.$patch",
    contact   => cstring($data, $l, 'CONTACT'),
    build     => cstring($data, $l, 'BUILD'),
    crc32     => sprintf('%08x', stored_crc($data, $l)),
    reset     => sprintf('%04x', unpack('v', substr($data, 0xFFFC - $ROM_BASE, 2))),
  );
}

my ($cmd, $file) = @ARGV;
die "usage: $0 patch|verify|info IMAGE\n"
  unless defined $file && @ARGV == 2 && $cmd =~ /\A(?:patch|verify|info)\z/;

my $layout = read_ident_layout();
$IDENT_END = $layout->{IDENT_BASE} - $ROM_BASE + $layout->{IDENT_SIZE};
my $data = read_image($file);
check_ident($file, $data, $layout);

if ($cmd eq 'patch') {
  my ($crc, $blocks) = compute_crcs($data, $layout);
  substr($data, field($layout, 'CRC'), 4) = pack('V', $crc);
  substr($data, field($layout, 'BCRC'), $layout->{IDENT_BCRC_LEN}) = pack('V*', @$blocks);
  write_image($file, $data);
  printf "%s: CRC-32 %08x and %d block CRCs patched\n", $file, $crc, scalar @$blocks;
} elsif ($cmd eq 'verify') {
  check_vectors($file, $data);
  my ($stored, $sblocks) = stored_crcs($data, $layout);
  my ($crc, $blocks) = compute_crcs($data, $layout);
  die sprintf("%s: CRC-32 stored %08x, computed %08x\n", $file, $stored, $crc)
    if $stored != $crc;
  for my $n (0 .. $#$blocks) {
    die sprintf("%s: block %d CRC-32 stored %08x, computed %08x\n",
      $file, $n, $sblocks->[$n], $blocks->[$n]) if $sblocks->[$n] != $blocks->[$n];
  }
  my %i = info($data, $layout);
  die "$file: version string '$i{version}' does not match bytes $i{version_n}\n"
    unless $i{version} =~ /\A\Q$i{version_n}\E(?:-|\z)/;
  printf "%s: OK, %d bytes, %s %s, built %s, CRC-32 %s\n",
    $file, length($data), $i{name}, $i{version}, $i{build}, $i{crc32};
} else {
  my %i = info($data, $layout);
  say "$_=$i{$_}" for qw(name version contact build crc32 reset);
}
