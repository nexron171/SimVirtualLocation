# SimVirtualLocation

Easy to use MacOS 11+ application for easy mocking iOS device and simulator location in realtime. Built on top of  [set-simulator-location](https://github.com/MobileNativeFoundation/set-simulator-location) and [idevicelocation](https://github.com/JonGabilondoAngulo/idevicelocation). Android support is realized with [SimVirtualLocation](https://github.com/nexron171/android-mock-location-for-development) android app which is fork from [android-mock-location-for-development](https://github.com/amotzte/android-mock-location-for-development).

Posibilities:
- supports both iOS and Android
- set location to current Mac's location
- set location to point on map
- make route between two points and simulate moving with desired speed

You can dowload compiled and signed app [here](https://github.com/nexron171/SimVirtualLocation/releases).

![App Screen Shot](<simvirtuallocation.png>)

## FAQ
---
### How to run
If you see an alert with warning that app is corrupted and Apple can not check the developer: try to press and hold `ctrl`, then click on SimVirtualLocation.app and select "Open", release `ctrl`. Now alert should have the "Open" button. Don't forget to copy app from dmg image to any place on your Mac.

### For iOS devices
`libimobiledevice` and `libzip` are should be installed on mac ? through `brew`

```shell
brew install libimobiledevice && brew install libzip
```

### If iOS device is unlisted

Try to refresh list and if it does not help - go to Settings / Developer and click Clear trusted computers. Replug cable and press refresh. If it still not in list - go to Xcode / Devices and simulators and check your device, there are should not be any yellow messages. If it has - make all that it requires.

---
### For Android
1. Check if debugging over USB is enabled
1. Specify ADB path (for example `/User/dev/android/tools/adb`)
1. Specify your device id (type `adb devices` in the terminal to see id)
1. Setup helper app by clicking `Install Helper App` and open it on the phone
1. Grant permission to mock location - go to Developer settings and find `Application for mocking locations` or something similar and choose SimVirtualLocation
1. Keep SimVirtualLocation running in background while mocking
