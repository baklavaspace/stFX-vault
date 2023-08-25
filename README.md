# stFX-vault

The stake FX Liquid Staking Protocol allows their users to earn staking rewards on the FunctionX chain without locking FX or maintaining staking infrastructure.

Users can deposit FX to the Baklava smart contract and receive stFX tokens in return. The smart contract then stakes tokens with the governance-picked node validators. Users' deposited funds are delegated by the smart contract, node validators never have direct access to the users' assets.

The stFX token is free from the limitations associated with a lack of liquidity and can be transferred at any time. The stFX token balance corresponds to the amount that the holder could request to withdraw.

Before getting started with this repo, please read:

* [Documentation](https://baklavaspace.gitbook.io/main/about/introduction)


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
