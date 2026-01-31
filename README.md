# wpm

a terminal typing test written in zig. only tested on macos. 

## build

```
zig build
```

## run

```
zig build run
```

optionally specify the number of words:

```
zig build run -- 25
```

## controls

- type the words shown on screen
- press `ESC` to quit
- press ` to toggle between hiscores and gameplay
- scores are saved to `~/.wpm/scores.dat`
