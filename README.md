# wpm

a terminal typing test written in zig.

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
- press `q` to quit
- scores are saved to `~/.wpm/scores.dat`
