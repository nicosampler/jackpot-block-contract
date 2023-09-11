pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

import "forge-std/Test.sol";

import "../src/MyLuckyBlock.sol";

contract MyLuckyBlockTest is Test {
    MyLuckyBlock public lottery;
    IERC20 public token;
    address admin;
    address donor;
    address bettor0;
    address bettor1;
    address bettor2;
    address bettor3;
    address bettor4;
    address bettor5;
    address bettor6;
    address bettor7;
    address bettor8;
    address bettor9;

    uint256 betPrice;
    uint256 amountOfHashesToDetermineWinner;

    function setUp() public {
        admin = address(0x1);
        donor = address(0x2);
        bettor0 = address(0x50);
        bettor1 = address(0x51);
        bettor2 = address(0x52);
        bettor3 = address(0x53);
        bettor4 = address(0x54);
        bettor5 = address(0x55);
        bettor6 = address(0x56);
        bettor7 = address(0x57);
        bettor8 = address(0x58);
        bettor9 = address(0x59);

        token = new ERC20PresetFixedSupply("USDT", "USDT", 1000000 ether, admin);
        vm.startPrank(admin);
        token.transfer(bettor0, 10000 ether);
        token.transfer(bettor1, 10000 ether);
        token.transfer(bettor2, 10000 ether);
        token.transfer(bettor3, 10000 ether);
        token.transfer(bettor4, 10000 ether);
        token.transfer(bettor5, 10000 ether);
        token.transfer(bettor6, 10000 ether);
        token.transfer(bettor7, 10000 ether);
        token.transfer(bettor8, 10000 ether);
        token.transfer(bettor9, 10000 ether);
        vm.stopPrank();

        vm.prank(admin);
        token.transfer(donor, 10000 ether);

        betPrice = 5 ether;
        uint256 blocksBetweenRound = 10;
        amountOfHashesToDetermineWinner = 3;
        uint256 maxBetValue = 9;

        vm.roll(block.number - 100);

        lottery = new MyLuckyBlock(
            address(token),
            betPrice,
            blocksBetweenRound,
            amountOfHashesToDetermineWinner,
            maxBetValue,
            admin
        );
    }

    function testDonate() public {
        uint256 amount = 1 ether;

        vm.prank(donor);
        token.approve(address(lottery), amount);
        vm.prank(donor);
        lottery.donate(amount);

        assertEq(lottery.poolPrize(), amount);
    }

    function testPlaceBetWithZeroAddress() public {
        uint24 betValue = 9999; // Asumiendo que 9999 es un valor válido de apuesta

        vm.prank(bettor1);
        token.approve(address(lottery), 1 ether);

        vm.expectRevert(MyLuckyBlock.AddressZero.selector);
        lottery.placeBet(betValue, address(0));
    }

    function testPlaceBetAfterTargetBlock() public {
        vm.roll(lottery.targetBlock() + 1);

        vm.expectRevert(MyLuckyBlock.BetIsClosed.selector);
        vm.prank(bettor1);
        lottery.placeBet(1234, bettor1);
    }

    function testPlaceBetWithInvalidValue() public {
        uint24 bet = 10000;

        vm.expectRevert(MyLuckyBlock.InvalidBetValue.selector);
        lottery.placeBet(bet, donor);
    }

    function testPlaceBetTransferFailed() public {
        vm.prank(bettor1);
        token.approve(address(lottery), betPrice - 1);

        vm.prank(bettor1);
        vm.expectRevert();
        lottery.placeBet(642, bettor1);
    }

    function testPlaceBetSuccess() public {
        uint256 initialPrizePool = lottery.poolPrize();
        uint256 initialTotalFees = lottery.totalFees();

        vm.prank(bettor1);
        token.approve(address(lottery), betPrice);
        vm.prank(bettor1);
        lottery.placeBet(6, bettor1);

        uint256 betFee = (betPrice * lottery.BET_FEE()) / lottery.BASIS_POINTS();
        uint256 betAmount = betPrice - betFee;

        assertEq(lottery.poolPrize(), initialPrizePool + betAmount);
        assertEq(lottery.totalFees(), initialTotalFees + betFee);
    }

    function testWinnersDistribution() public {
        uint256 poolPrize;
        uint256[] memory initialBalances = new uint256[](10);
        uint256 targetBlock;

        // Simulate 10 players placing bets, each address bets its index
        for (uint8 i = 0; i < 10; i++) {
            address bettor = address(uint160(uint256(0x50) + i));
            uint24 betNumber = uint24(i); // each address bets its index

            vm.prank(bettor);
            token.approve(address(lottery), betPrice);
            lottery.placeBet(betNumber, bettor);

            initialBalances[i] = token.balanceOf(bettor);
        }

        // Fast-forward the blockchain to beyond the target block
        vm.roll(lottery.targetBlock() + amountOfHashesToDetermineWinner + 2);

        // save data before resolving the lottery
        targetBlock = lottery.targetBlock();
        poolPrize = lottery.poolPrize();

        // Resolve the lottery
        vm.prank(donor);
        lottery.resolveLottery();

        // Log the winning number
        uint24 winningNumber = lottery.getWinningNumber(targetBlock);
        emit log_string("Winner number");
        emit log_uint(winningNumber);

        // Retrieve the hashes used to calculate the winning number
        emit log_string("Hashes used to calculate the winning number");
        for (uint256 i = 0; i < amountOfHashesToDetermineWinner; i++) {
            bytes32 hash = blockhash(targetBlock + i);
            emit log_bytes32(hash);
        }

        // Retrieve the winner based on the winning number
        address winner = lottery.getBettors(targetBlock, winningNumber)[0];
        emit log_string("Winner address");
        emit log_address(winner);

        // Validate the token balance of the winner
        uint256 winnerInitialBalance = initialBalances[winningNumber];
        uint256 winnerPrizeAmount = (poolPrize * lottery.FIRST_ROUND_WINNER_PERCENTAGE()) / lottery.BASIS_POINTS();

        emit log_string("Winner price:");
        emit log_uint(winnerPrizeAmount);

        emit log_string("Winner prev balance:");
        emit log_uint(winnerInitialBalance);

        emit log_string("Winner current balance:");
        emit log_uint(token.balanceOf(winner));

        emit log_string("Winner prize amount:");
        emit log_uint(winnerPrizeAmount);

        uint256 expectedFinalBalance = winnerInitialBalance + winnerPrizeAmount;
        assertEq(token.balanceOf(winner), expectedFinalBalance);

        // Validate that the contract has been reset for the next round.
        uint256 expectedPoolPrize = (poolPrize * (lottery.BASIS_POINTS() - lottery.FIRST_ROUND_WINNER_PERCENTAGE())) /
            lottery.BASIS_POINTS();
        assertEq(lottery.poolPrize(), expectedPoolPrize);

        emit log_string("Pool poolPriceer resolve:");
        emit log_uint(lottery.poolPrize());
    }
}
