// npx hardhat run scripts/deploy.js --network fxMainnet

const { ethers, upgrades } = require('hardhat');

function tokens(n) {
  return ethers.utils.parseUnits(n, '18');
}

async function main() {
    const [deployer] = await ethers.getSigners();

    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Account balance:", (await deployer.getBalance()).toString());



    // ============ Deploy StakeFXVault ============

    const StakeFXVault = await ethers.getContractFactory("StakeFXVault");
    // const stakeFXVault = await upgrades.deployProxy(StakeFXVault, [asset, owner, governor], {kind: "uups", timeout: '0', pollingInterval: '1000'});
    // await stakeFXVault.deployed();


    console.log("Contract address:", stakeFXVault.address);

    // ============ Deploy FXFeesTreasury ============

    // const FXFeesTreasury = await ethers.getContractFactory("FeeTreasury");
    // const fxFeesTreasury = await upgrades.deployProxy(FXFeesTreasury, [], {kind: "uups", timeout: '0', pollingInterval: '1000'});
    // await fxFeesTreasury.deployed();

    // console.log("Contract address:", fxFeesTreasury.address);

    // ============ Deploy VestedFX ============

    // const VestedFX = await ethers.getContractFactory("VestedFX");
    // const vestedFX = await upgrades.deployProxy(VestedFX, [stFX, fxFeesTreasury.address], {kind: "uups", timeout: '0', pollingInterval: '1000'});
    // await vestedFX.deployed();
    
    // console.log("Contract address:", vestedFX.address);


    // ============ Deploy RewardDistributor ============

    // const RewardDistributor = await ethers.getContractFactory("RewardDistributor");
    // const rewardDistributor = await upgrades.deployProxy(RewardDistributor, [reward, stFX, owner, owner], {kind: "uups", timeout: '0', pollingInterval: '1000'});
    // await rewardDistributor.deployed();

    // console.log("Contract address:", rewardDistributor.address);

    // ============ Deploy MultiCall ============

    // const MultiCall = await ethers.getContractFactory("MultiCall");
    // const multiCall = await upgrades.deployProxy(MultiCall, [stFX], {kind: "uups", timeout: '0', pollingInterval: '1000'});
    // // await multiCall.deployed();

    // console.log("Contract address:", multiCall.address);
  
  }
  
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
