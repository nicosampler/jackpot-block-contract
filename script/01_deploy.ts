import * as dotenv from "dotenv";
import hre from "hardhat";
import { HardhatRuntimeEnvironment } from "hardhat/types";

dotenv.config();

async function main(hre: HardhatRuntimeEnvironment) {
  const { ethers } = hre;
  const [deployer] = await ethers.getSigners();

  //  const JpContract = await ethers.getContractFactory("JackpotBlock");

  console.log("Deploying contract...");
  const jpContract = await ethers.deployContract(
    "JackpotBlock",
    [
      //address _betTokenAddress
      "0x98339D8C260052B7ad81c28c16C0b98420f2B46a",
      //uint256 _betPrice
      "1000000",
      //uint256 _blocksBetweenRound
      60,
      //uint256 _amountOfHashesToDetermineWinner
      5,
      //uint256 _maxBetValue
      99,
      //address _feeCollector
      "0xDe75665F3BE46D696e5579628fA17b662e6fC04e",
      //uint256 _betFee
      1000,
    ],
    deployer as any,
  );

  await jpContract.deployed();

  console.log("Deployed at address:", jpContract.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main(hre).catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
