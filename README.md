# $Commit-Reveal^{2}$

A secure and efficient implementation of the $Commit-Reveal^{2}$ protocol, offering both fully on-chain and hybrid off-chain leveraged solutions for randomness generation.

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
