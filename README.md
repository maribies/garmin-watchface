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

## Sprite Development
Used pixilart (https://www.pixilart.com/).

# Running the project locally
Open the `DogAnimationExperiment` folder directly as the VSCode workspace root (File > Open Folder), not the parent `garmin-experiment` repo. The Monkey C extension resolves the jungle file and manifest paths relative to the workspace root, so opening the parent folder instead causes "Connect IQ project not found" / manifest lookup errors.

Before running the program, make sure you have one of your source files (In the source folder with the .mc extension) open and selected in the editor.

Select Run > Run Without Debugging (Command + F5 on Mac)

You will be prompted with the list of products your application supports. Select one from the list.
