# Garmin Experiment for Watchface Development

This is a test project to experiment with Garmin watchface development.

Building off of the [example app](https://github.com/garmin/connectiq-companion-app-example-ios).

# Requirements

I would like to create a watchface of a cute dog, perhaps a corgi, that is animated to spin (chasing its tail), lick (the screen), and bark with hearts at varying intervals.

I also want the watchface to show basic information, like the date, time, steps, and battery level. 

This watchface will be for the Garmin Fenix 7S Pro Sapphire Solar watch. We need to verify compatibilty, but I believe that we will be targeting API Level 5.2 or higher. 

Here are some animation examples:
[VS code pets](https://github.com/tonybaloney/vscode-pets)
[Garmin Corgi example](https://apps.garmin.com/apps/d5cf60d2-4ec6-4450-b082-0b3a9adea6bd?tab=reviews&criteria=rating&ascending=true&displayCurrentVersion=true)

We should add clear testing documentation as we are developing.

## Plan
The instructions to create a new monkey c project [from Garmin](https://developer.garmin.com/connect-iq/connect-iq-basics/your-first-app/#your-first-connect-iq-app) to initalize the project have been followed and live in the directory named DogAnimationExperiment.

We should start with just displaying the required information and the dog in a sitting position. 

If animation is proving to be difficult, we should probably start with a simple blinking eyes animation. Then we can move to the next least challenging animation, which is probably the licking of the screen, or the bark, since the dog can remain in the seated position and just the mouth would need animated. 

The tail chasing sping animation, being the most complicated and requiring the most movement, should be saved for last.

A developer key has been generated during the project initalization and is stored in a gitignored file in this project, but should probably be moved.

Work followed [planning/coding-strategy.md](planning/coding-strategy.md) through the initial phases (static display, standing-idle animation, and the lick/sit-stand/tail-spin tricks). Further work continues in [planning/refinement-strategy.md](planning/refinement-strategy.md), covering a visual redesign and additional animated behaviors.

The project setup and key API findings are noted in [boilerplate-context.md](boilerplate-context.md).

## Sprite Development
Used pixilart (https://www.pixilart.com/) and Claude design.

A recipe for creating the pixel art has been documented and is continuously updated in [sprite-recipe.md](sprite-recipe.md) to track the strategy creation of the pixel art and to hopefully provide key insights to additional "breed" development in the future.

## Icons
UI icons (steps, battery, etc.) are sourced from [Font Awesome Free](https://fontawesome.com/) — icons are CC BY 4.0, fonts are SIL OFL 1.1, code is MIT. All three require attribution. See the "Before publishing" note in [refinement-strategy.md](planning/refinement-strategy.md) for what that means for this app specifically (a compiled `.prg` doesn't carry forward the source file's embedded license comments the way a served web asset would).

## Large-screen resources
The dog and the field icons are scaled up at build time on the larger (360–454px) screens. `monkey.jungle` maps each screen size to a generated override folder:

| Folder | Screens | Sprites | Field icons | Battery icon |
|---|---|---|---|---|
| `resources/` (base) | 218–280 | 1× | 16px tall | 20px tall |
| `resources-large-150` | 360, 390, 416 | 1.5× | 26px tall | 33px tall |
| `resources-large-200` | 454 | 2× | 29px tall | 37px tall |

Both folders are **generated** from `resources/drawables/drawables.xml` by `scripts/generate-large-screen-resources.py`. The script also builds each breed's `<palette>` from the colors in its sprite sheets, which keeps scaled pixel art from being smoothed into extra colors. Don't edit the generated files. After adding or changing a sprite or icon in the base file, regenerate and commit the result:
```
scripts/generate-large-screen-resources.py
```
`scripts/build.sh` runs it with `--check` first and stops if the generated files are out of date. To change a scale or icon height, edit `LARGE_SCALES` in the script. Icons are rasterized at the size they're drawn and drawn unscaled, because `Dc.drawScaledBitmap` doesn't exist on some supported devices (fr165, fr255 family, vivoactive5). To map a new screen size, add a line to `monkey.jungle`.

# IQ Connect Description

Draft copy for the Connect IQ Store listing description (update before actually publishing — see the "Before publishing" checklist in [refinement-strategy.md](planning/refinement-strategy.md)).

Needs:
- title (max 50 chars)
   - Pixel Dog Animation
- description (max 4000 chars)
   - see below
- What's new (optional - max 4000 chars)
- hero image (optional - The image (JPG, GIF or PNG) has to be 1440x720 pixels large and can have a maximum size of 2048 KB.)
   - saved in designs
- Category and Subcategory selection
   - fun
- Privacy policy, if app collects user data (boolean)
- ANT+ Profiles (boolean)
- Regional Limits (boolean)
- Cover Image & Icons (Image must be a JPG, GIF or PNG less than 300 KB.). Icons (boolean - only be 128 x 128 pixels, device 64 and 24 color)
- Screen images (Image must be a JPG, GIF or PNG less than 150 KB)
- Preview video (optional- YouTube and Vimeo only)
- Additional information - email (public) and source code url
- Review notification (boolean)
- App migration (boolean)
- Monetization (boolean)
- Companion App (optional)
- Additional hardware requirements (link)

A cute pixel dog watch face that idles, blinks, and plays random tricks (tail spin, licking the screen, sitting down and standing back up). Background color and data fields are fully customizable via the on-watch settings menu. 

Choose up to 6 of the following stat fields, shown around the dog:
- **Steps** — today's step count
- **Heart Rate** — most recent heart rate reading
- **Weather** — today's forecasted high/low temperature
- **Body Battery** — current body battery level
- **Calories** — calories burned today
- **Notifications** — unread notification count
- **Floors Climbed** — floors climbed today
- **Intensity Minutes** — this week's accumulated intensity minutes
- **Distance** — distance traveled today

Also customizable: background color (6 shades) and 12/24-hour time format.

Currently just a corgi-like animation, hopefully other breeds and trick animations soon.

Developed with the help of Claude code.

Icons: Font Awesome Free 7.3.1 (fontawesome.com), © Fonticons, Inc., CC BY 4.0 (creativecommons.org/licenses/by/4.0) — converted to bitmap and recolored.

# Running the project locally
## In simulation
Open the `DogAnimationExperiment` folder directly as the VSCode workspace root (File > Open Folder), not the parent `garmin-experiment` repo. The Monkey C extension resolves the jungle file and manifest paths relative to the workspace root, so opening the parent folder instead causes "Connect IQ project not found" / manifest lookup errors.

Before running the program, make sure you have one of your source files (In the source folder with the .mc extension) open and selected in the editor.

Select Run > Run Without Debugging (Command + F5 on Mac)

You will be prompted with the list of products your application supports. Select one from the list.

## Side load on the device
From section [Side Loading an App](https://developer.garmin.com/connect-iq/connect-iq-basics/your-first-app/)

The Monkey C extension provides a wizard to help developers side load an application. The wizard will create an executable (PRG) of the selected project. Here's how to use it:

Plug your device into your computer
* Mac users need the Garmin (Android) device to be discoverable. Suggested download is [openmtp](https://github.com/ganeshrvel/openmtp).

Use Ctrl + Shift + P (Command + Shift + P on the Mac) to summon the command palette
* Make sure to do this in the `DogAnimationExperiment` as explained above in the simulation section.

In the command palette type "Build for Device" and select Monkey C: Build for Device

Select the product you wish to build for. If you are unable to choose a device for which to build (the menu appears empty), it means that there are no valid devices configured for your project. See Editing the Supported Products for instructions.

Choose a directory for the output and click Select Folder

In your file manager, go to the directory selected in step 4

Copy the generated PRG files to your device's GARMIN/APPS directory

Apparently the PRG files are not visible, and the only way to verify is by checking if the new watchface appears in the options, otherwise it can just silently fail.

The success of side loading appears to be mixed and the alternative is upload the App for beta in th IQ format on [Garmin's developer website](https://apps.garmin.com/en-US/developer/upload). See the next section.
** A Note from Garmin: Only you will be able to download and test the app. If you want to publish your app after testing, you will need to upload it again and use another appID in the app’s manifest.xml. **

## Build for release (.iq)
The `.iq` format needed for beta testing or Store submission via [Garmin's developer upload page](https://apps.garmin.com/en-US/developer/upload) is a different artifact from the per-device `.prg` files above — it bundles every manifest-declared device into one release-optimized package. This is a different VS Code command than "Build for Device" used above — use "Monkey C: Export Project" from the command palette, or via CLI (`-e` is the export/package flag), from the repo root:
```
monkeyc -e -r -w -f DogAnimationExperiment/monkey.jungle -o DogAnimationExperiment/bin/DogAnimationExperiment.iq -y keys/developer_key
```
`-e` exports the Store-ready package instead of a single device's `.prg`; `-r` builds in release/optimized mode; `-w` shows compiler warnings. Output lands at `DogAnimationExperiment/bin/DogAnimationExperiment.iq`, ready to upload.

### Beta App
Manifest AppID: b4605c40f90b48e7a9b6432924bece6e
https://apps.garmin.com/apps/a3e115df-0f42-4b7b-8aa9-12abb13b5406
Use another appID in the app’s manifest.xml to publish.

From the Beta page, under Manage Your App, click download. This will pop up to confirm the device to install the watchface and then open Garmin Express to finish the installation. 

# Running Tests

Unit tests live alongside the source they cover, in files ending `Tests.mc` (e.g. `DogAnimationExperimentViewTests.mc`), using Garmin's built-in `Toybox.Test` framework. Test functions are tagged `(:test)`.

## Via VSCode
Open the Testing sidebar (flask icon), or use the Command Palette: "Monkey C: Run Test Explorer".

## Via script
`scripts/build.sh` builds every device the manifest declares, then builds and runs the test suite on `fenix7s` — the same sequence otherwise typed by hand. Auto-detects the installed SDK; override with `CONNECTIQ_SDK_HOME` if more than one is installed.
```
scripts/build.sh
```

## Via CLI
Useful when you want plain PASS/FAIL output without driving the simulator UI (`monkeyc`/`monkeydo` are in the Connect IQ SDK's `bin/` folder; check VSCode's Monkey C SDK setting if they're not on your `PATH`):

1. Launch the simulator and leave it running: `open -a "<path-to-sdk>/bin/ConnectIQ.app"`
2. Build with tests included:
   ```
   monkeyc -f DogAnimationExperiment/monkey.jungle -d fenix7s -o /tmp/watch_tests.prg -y keys/developer_key -t
   ```
3. Run the tests against the simulator:
   ```
   monkeydo /tmp/watch_tests.prg fenix7s -t
   ```
   This prints a PASS/FAIL result per test plus a summary — no manual interaction with the simulator window needed.
