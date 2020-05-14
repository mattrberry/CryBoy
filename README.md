# CryBoy ![CryBoy Graphic](README/gameboy.png)

CryBoy is a Gameboy emulator written in Crystal. The goal of this project is an efficient Gameboy emulator with highly readable code. So far, neither aspect of the goal is accomplished.

This would not be possible without the [Pan Docs](https://bgb.bircd.org/pandocs.htm). A thanks also goes out to [PyBoy](https://github.com/Baekalfen/PyBoy), which was occasionally used as a reference.

## Installation

SDL2 is a requirement for this project. install that however you see fit.

After cloning the respository, you'll need to install the required shards with `shards install`.

## Usage

After installing the dependencies, the project can be build with `shards build --release`. At this point, the binary lives in `bin/gb`. The binary takes a rom path as its only argument: `bin/gb /path/to/rom`.

## Contributing

1. Fork it (<https://github.com/mattrberry/gb/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Matthew Berry](https://github.com/mattrberry) - creator and maintainer
