# Design Log

This directory contains screen shots. I explain each shot and the design decisions behind it here.

## 2015-01-11-letter-boxing.png

**Git commit**: 44d5b8315bd330f4a22afe0e7b8dc3a2cc8a1647

The game field is now a 4:3 aspect ratio. On most mobile devices this will mean letterboxing
at the left and right of the screen. For those rare devices that have more square screens this will
mean letterboxing at the top and bottom. So I'm not using some of the screen real estate. I don't
know whether this is stupid or not, but providing a larger playing area on certain devices
just because they have a larger aspect ratio means that you have a distinct gameplay experience
(and probably an advantage over those playing on devices with a smaller aspect ratio).

You'll notice in the pic that the "Infected!" message only covers the game area. I might
change this in the future.

## 2015-01-21-antibiotics.png

**Git commit**: f7c29d8e5c1d55e9ec51ed626dfbc12bad2d6d6e

The antibiotics are shown as a big circle with an "effectiveness" written inside them.
The term "x% effective" means that *on average* x% of the germs die. What this really means
is that each germ has a small chance, equal to (100 - x)%, of being immune to the antibiotic.

At the moment you click on the antibiotic to use it. In future I will require a drag-and-drop
action in order to use. I am still undecided about whether the antibiotics applies to all the germs
or an area of effect based on where it was dropped. Probably the former as the latter has
implications for strategy and design. The implication on design is that I'll have to signify
somehow the area of effect.

## 2015-01-22-mutation.png

**Git commit**: 68565a0be335d4e65fd55485acb9c994846f246e

The germs now mutate and inherit from each other.
