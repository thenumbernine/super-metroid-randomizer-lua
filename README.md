# Super Metroid item randomizer

Depends on:
- LuaJIT
- my lua ext library
- my lua template library
- my lua ips library

randomizes the following:
- enemies:
	- item drop percentages 
	- weaknesses 
	- health
	- touch damage
	- shot damage
- item placement

The item placement algorithm does a depth-first search to make sure that there is at least one possible run that will result in the game being won.

It takes into account required items to enter the room, to leave the room, enemy weaknesses (for grey doors), and what skills the player knows.

This doesn't mean that you can't get permanently stuck in a room.  It just means that somewhere you can access the item that you need to get unstuck.  So save often.

Item placement also allows you to replace certain items.  In case you wanted to see what a run through of Super Metroid was like with only 6 energy tanks.

Item placement also allows for changing the probability of placing an item.  In case you wanted to put all the super missiles and e-tanks at the end of the game.


My next goal is to randomize doors, then maybe even blocks in certain passageways.

### I have added a dump of all memory ranges that I am using -- in an attempt to better chart out the ROM:

[memory map](memorymap.txt)

### I've got rooms decompressing correctly.  Here's proof:

![map of Super Metroid](map.png)


