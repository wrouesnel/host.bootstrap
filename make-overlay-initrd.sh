#!/bin/bash
# Make overlay initrd builds an an initrd from the given directory. This can
# be passed via a loader like pixiecore to customize the boot environment
# without a rebuild.

out_file=$1
source_dir=$2

[ -z "$out_file" ] && echo "Must specify an output file." && exit 1
[ -z "$source_dir" ] && echo "Must specify a source directory." && exit 1

echo "Building compressed initrd: $out_file"
pwd="$(pwd)"
cd "$source_dir" || exit 1
# Command which builds the initramfs
find . | cpio -H newc -o | gzip -c > "$pwd/$out_file" || exit 1
cd "$pwd"
