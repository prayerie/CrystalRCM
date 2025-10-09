![](banner_new.png)

A native port of fusée-launcher frontend for macOS (Universal). **Supports macOS >= 10.12.**

It uses native IO libraries, so doesn't require any external downloads.

All credit to Qriad who made the [original launcher](https://github.com/Qyriad/fusee-launcher) - this is just a Swift translation :-).


## Usage

![](ss1.png)

Select a payload, and then press 'push'. You can also optionally automatically push on USB connection. A future release will allow the app to run in the background.

The "Push!" button will be disabled if no payload is selected, or if a device in RCM is not detected. To force an attempt, hold shift, which will temporarily override and enable the push button.

Please note - the app may not work unless you move it outside of the distribution .dmg.

## Building

Currently, it will be a bit annoying to build as there are some hardcoded paths in the Xcode project. However, other than that, it should be as simple as opening the project in Xcode and building for yourself.

## How to create (old)

If you wish to build the previous Python release, please switch to the "old" branch and follow the instructions there.

## Contact

If you run into any issues or have any questions, feel free to open an issue here, or contact me on Discord: @prayerie.
