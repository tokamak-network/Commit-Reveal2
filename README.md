## About
This repository contains an implementation of the **Commit-Reveal²** protocol, as described in the paper:

Suhyeon Lee and Euisin Gee, **"Commit-Reveal²: Randomized Reveal Order Mitigates Last-Revealer Attacks in Commit-Reveal,"** *ICBC 2025 - IEEE International Conference on Blockchain and Cryptocurrency, June 2025*

The Commit-Reveal² protocol ia a blockchain randomness generation mechanism using a two-layer commit-reveal process to reduce the last-revealer attack risk.

## Warning
The code in this repository has not been audited. Use it with caution. Thoroughly review and test the code before using it in a production environment.

## Directory Structure

<pre>
├── lib: Contains dependencies managed as Git submodules.
├── src: Main directory containing smart contracts.
├── test: Test files for Commit-Reveal^2 implementations.
│   ├── shared: Utility contracts, including quick sorting library.
</pre>

## Requirements

- [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
  - You'll know you did it right if you can run `git --version` and you see a response like `git version x.x.x`
- [foundry](https://getfoundry.sh/)
  - You'll know you did it right if you can run `forge --version` and you see a response like `forge 0.2.0 (75fc63b 2024-12-05T00:23:16.738603000Z)`

## Build

```
make install
make build
```

## Test

```
make test
```

Test results will be logged to the console.
Alternatively, you can review the results in the following JSON files:

- commitreveal2hybrid.json
- commitreveal2onchain.json
