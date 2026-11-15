# EmuDEN privacy policy

EmuDEN is a game launcher that runs on your own devices. It has no servers and no accounts of
its own, and it does not collect, sell or share data about you.

## Sync plugins

The sync plugins (Google Drive, RomM, Syncthing) copy your saves, save states, settings and,
if you choose, games between your own devices.

- **Google Drive** (`emuden.sync.gdrive`): after you sign in, EmuDEN uses Google's
  `drive.file` permission, which lets it see and change only the files EmuDEN itself created
  in your Drive (the `EmuDEN` folder). It cannot read any other file in your Drive. Your
  files go directly between your device and Google; they are not sent anywhere else. The
  sign-in token is kept in your device's credential store and never leaves the device except
  to Google. You can remove EmuDEN's access at any time at
  https://myaccount.google.com/permissions, and delete the `EmuDEN` folder from your Drive.
- **RomM**: files go only to the RomM server whose address you enter.
- **Syncthing**: files go only into a folder on your device, which your own Syncthing copies
  to the devices you chose.

EmuDEN's use and transfer of information received from Google APIs adheres to the
[Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy),
including the Limited Use requirements.

## Other connections

EmuDEN downloads plugins, cores and cover art from public sources (GitHub, the LaunchBox
image server, libretro's thumbnail server). These requests carry no personal information.

## Contact

Questions: open an issue at https://github.com/Denarmo/emuden-plugins/issues.
