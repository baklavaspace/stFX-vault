# stFX-vault

The stake FX Liquid Staking Protocol allows their users to earn staking rewards on the FunctionX chain without locking FX or maintaining staking infrastructure.

Users can deposit FX to the Baklava smart contract and receive stFX tokens in return. The smart contract then stakes tokens with the governance-picked node validators. Users' deposited funds are delegated by the smart contract, node validators never have direct access to the users' assets.

The stFX token is free from the limitations associated with a lack of liquidity and can be transferred at any time. The stFX token balance corresponds to the amount that the holder could request to withdraw.

Before getting started with this repo, please read:

* [Documentation](https://baklavaspace.gitbook.io/main/about/introduction)

## FunctionX mainnet：
```
StakeFXVault: [0x5c24B402b4b4550CF94227813f3547B94774c1CB](https://starscan.io/evm/address/0x5c24B402b4b4550CF94227813f3547B94774c1CB)
VestedFX: [0x37f716f6693EB2681879642e38BbD9e922A53CDf](https://starscan.io/evm/address/0x37f716f6693EB2681879642e38BbD9e922A53CDf)
FXFeesTreasury: [0xe48C3eA37D4956580799d90a4601887d77A57d55](https://starscan.io/evm/address/0xe48C3eA37D4956580799d90a4601887d77A57d55)
RewardDistributor: [0xea505C49B43CD0F9Ed3b40D77CAF1e32b0097328](https://starscan.io/evm/address/0xea505C49B43CD0F9Ed3b40D77CAF1e32b0097328)
Multicall: [0xF5E657e315d8766e0841eE83DeEE05aa836Cc8ce](https://starscan.io/evm/address/0xF5E657e315d8766e0841eE83DeEE05aa836Cc8ce)
```

## Local deployment
```
npx install
npx hardhat run scripts/deploy.js --network fxMainnet
```

# License

BAKLAVA.SPACE © 2021-2023

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, version 3 of the License, or any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the [GNU General Public License](LICENSE)
along with this program. If not, see <https://www.gnu.org/licenses/>.
