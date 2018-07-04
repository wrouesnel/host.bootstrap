SUITE=bionic
src=src
root=root
boot=boot
tmp=tmp
mnt=mnt

output_img=$boot/diskimage.qcow2
output_size=${output_size:-100G}

kvm_defaults=(\
    -nodefaults \
    -machine pc-i440fx-zesty,accel=kvm,usb=off,dump-guest-core=off  \
    -cpu host -realtime mlock=off -smp 2,sockets=2,cores=1,threads=1  \
    -uuid $(uuidgen)  \
    -no-user-config  \
    -rtc base=utc,driftfix=slew  \
    -global kvm-pit.lost_tick_policy=discard  \
    -no-hpet \
    -global PIIX4_PM.disable_s3=1  \
    -global PIIX4_PM.disable_s4=1  \
    -device ich9-usb-ehci1,id=usb,bus=pci.0,addr=0x5.0x7  \
    -device ich9-usb-uhci1,masterbus=usb.0,firstport=0,bus=pci.0,multifunction=on,addr=0x5  \
    -device ich9-usb-uhci2,masterbus=usb.0,firstport=2,bus=pci.0,addr=0x5.0x1  \
    -device ich9-usb-uhci3,masterbus=usb.0,firstport=4,bus=pci.0,addr=0x5.0x2  \
    -device virtio-serial-pci,id=virtio-serial0,bus=pci.0,addr=0x6  \
    -chardev pty,id=charserial0 -device isa-serial,chardev=charserial0,id=serial0  \
    -device qxl-vga,id=video0,ram_size=67108864,vram_size=67108864,vram64_size_mb=0,vgamem_mb=16,max_outputs=1,bus=pci.0,addr=0x2  \
    -msg timestamp=on \
)
