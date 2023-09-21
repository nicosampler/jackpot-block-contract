const { exec } = require("child_process");

function main() {
  const address = "0xa706A1f24945B158D9B4990BF39819366F1901B5";

  const token = "0x98339D8C260052B7ad81c28c16C0b98420f2B46a";
  const betPrice = "1000000";
  const blocksBetweenRound = 60;
  const amountOfHashesToDetermineWinner = 5;
  const maxBetValue = 99;
  const feeCollector = "0xDe75665F3BE46D696e5579628fA17b662e6fC04e";
  const betFee = 1000;

  exec(
    `npx hardhat verify --network goerli ${address} ${token} ${betPrice} ${blocksBetweenRound} ${amountOfHashesToDetermineWinner} ${maxBetValue} ${feeCollector} ${betFee}`,
    (err: unknown) => {
      if (err) {
        console.error(`Error: ${err}`);
      }
    },
  );
}

main();
