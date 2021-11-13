# About NimUE4

Welcome. NimUE4 is an upcoming attempt at directly integrating the Nim programming language into Unreal Engine 4, allowing games made with UE4 to be written in and scripted with Nim. Support for UE5 will _probably_ be added at some point after its full public release. NimUE4 was originally created by [Pragmagic, Inc.](http://pragmagic.io/), a software company and video game developer based out of Delaware. Pragmagic ceased maintenance of NimUE4 in July of 2017, after which I took over development in the autumn of 2021. At the time of its initial drop, NimUE4 was not feature-complete. It still isn't, but the basis was there and worked, and I will try to complete the Unreal API where Pragmagic left off. Development will not go blazingly fast, as I have other projects to tend to as well (Most notably a Laravel-based web application and database that is due to be finished by May of 2022), but I will do my best to continue NimUE4 whenever I feasibly can, hopefully into eventual completion.

Important to note is that, given the incomplete state of NimUE4, I currently disrecommend the serious use of NimUE4 in production; at least until the API is complete, its use should be restricted to experiments and toy projects, unless you're 100% sure that all parts of the API you need for your game are properly implemented. Secondly, as mentioned before, NimUE4 is a project I intend to work on in my spare time, with my own pacing, and void of stress. There are no deadlines for me to meet (After all, NimUE4's use is currently unlikely as a result of its incompletion and obscurity) and I am not employed or contracted to develop this project. I will work on NimUE4 solely out of my own volition and only when doable within my work schedule. This does not mean that NimUE4 will take forever to progress, but don't expect lightspeed updates either. After all, this is currently a one-man, spare-time project.

The original README by Pragmagic is included below. When NimUE4 is closer to completion, I'll eventually move the original text to another file (an archive file, probably something like README-old.md) and rewrite the whole thing below.

# Nim Integration for Unreal Engine 4 [![Build Status](https://travis-ci.org/pragmagic/nimue4.svg?branch=master)](https://travis-ci.org/pragmagic/nimue4)

This repo contains Nim library and tools that allow to create Unreal Engine 4 games on [Nim programming language](http://nim-lang.org/).


The integration is in early development, so breaking changes are possible - backward compatibility is not guaranteed yet.


This integration is being used by an indie development team to create a mobile strategy game. That game runs on iOS, Android, Windows and Mac.

## Why Nim?

Nim is a native programming language that allows excellent programming productivity while not sacrificing the application's performance. It compiles directly into C++, so almost all the features UE4 provides can be made available in Nim.


Nim's syntax and semantics are simple and elegant, so Nim can be easily taught to scripters in game development teams. Nim also has rich support for meta-programming, allowing you to extend capabilities of Nim, which is great for the variety of domains a game developer usually encounters.

## Features

* Gameplay programming (most of the basic classes are available, more wrappers coming soon)
* Blueprint support
* Delegate declaration and usage support
* Support for UProperty and UFunction macros and their specifiers

The integration lacks support for:

* Creating editor extensions (coming soon)
* Creating Unreal plug-ins with Nim
* Debugging Nim code directly. But since Nim functions map to C++ functions clearly, you can use existing C++ debugging and profiling tools.

## Getting Started

See the [Getting Started](https://github.com/TheWitheredStriker/nimue4/wiki/Getting-Started) page on the wiki.

If you are new to Nim, make sure to see the [Learn section](http://nim-lang.org/learn.html) of the Nim's website.

See [NimPlatformerGame](https://github.com/pragmagic/NimPlatformerGame) repo for a sample of a game written on Nim.

## Documentation

See the repo's [wiki](https://github.com/TheWitheredStriker/nimue4/wiki/) for nimue4 documentation.

See the Nim website's [documentation section](http://nim-lang.org/documentation.html) for the Nim language documentation.

## Community
[![Join Nim Gitter channel](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/nim-lang/Nim)

If you have any questions or feedback for nimue4, feel free to submit an issue on GitHub.

* [Gitter](https://gitter.im/nim-lang/Nim) - you can discuss Nim and nimue4 here in real-time.
* The [Nim forum](http://forum.nim-lang.org/) - a place where you can ask questions and discuss Nim.

## Roadmap

High priority roadmap items include:

* Automated generation of wrappers for UE4 types
* UE4 plug-in that improves editor experience when working with Nim projects

## License

This project is licensed under the MIT license. Read [LICENSE](https://github.com/TheWitheredStriker/nimue4/blob/master/LICENSE) file for details.

Copyright (c) 2016 Xored Software, Inc.
