const { exec } = require("child_process");

function main() {
  const address = "0x367Fd09F5cD2c7ceB598D28b8a1e0721D2BA78C2";
  const token = "0x98339D8C260052B7ad81c28c16C0b98420f2B46a";
  const betPrice = "1000000";
  const blocksBetweenRound = 60;
  const amountOfHashesToDetermineWinner = 3;
  const maxBetValue = 99;
  const feeCollector = "0xDe75665F3BE46D696e5579628fA17b662e6fC04e";
  const betFee = 10;

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
