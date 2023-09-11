// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

// This contract represents a betting game where participants can bet on a winning number.
// The winning number is calculated based on amountOfHashesToDetermineWinner block hashes in the future.
contract JackpotBlock is Ownable, Pausable {
    // State variables
    address public betTokenAddress; // Address of the betting token
    uint256 public targetBlock; // Target block number to decide the round's winner.
    uint256 public poolPrize; // Prize pool in bet tokens
    uint256 public blocksBetweenRound; // Number of blocks between each round
    address public feeCollector; // Address that collects fees
    uint256 public totalFees; // Accumulated fees
    uint256 public maxBetValue; // Bet value for the current round
    uint256 public betPrice; // Cost of a single bet
    uint256 public amountOfHashesToDetermineWinner; // Amount of block hashes to use to determine the winner

    uint256 public betPriceForNextRound; // Cost of a single bet for the next round
    uint256 public maxBetValueForNextRound; // Maximum allowed bet value for the next round (0-9, 0-99, ... 0-999999)

    uint256 public constant BASIS_POINTS = 1000; // 1000 basis points = 100%
    uint256 public constant BET_FEE = 30; // 30 basis points = 3%
    uint256 public constant FIRST_ROUND_WINNER_PERCENTAGE = 800; // 800 basis points = 80%
    uint256 public constant SECOND_ROUND_WINNER_PERCENTAGE = 500; // 500 basis points = 50%

    // Keeps track of the block numbers for which bets have been placed.
    // blockNumber => betNumber => [bettor1, bettor2, ...]
    mapping(uint256 => mapping(uint24 => address[])) public bets;
    // Keeps track of which target blocks have been processed to ensure each is processed only once.
    // targetBlock => processed
    mapping(uint256 => bool) public targetBlocksProcessed;
    // Keeps track of which addresses have already placed a bet for a given target block.
    // targetBlock => betNumber => bettor => hasBet
    mapping(uint256 => mapping(uint24 => mapping(address => bool)))
        public hasBet;

    // Events
    event BetPlaced(
        address indexed bettor,
        address indexed onBehalfOf,
        uint256 blockNumber,
        uint24 bet
    );
    event PrizeClaimed(uint256 attempt, uint256 winners, uint256 amount);
    event DonationReceived(address indexed donor, uint256 amount);
    event newConfig(
        uint256 maxBetValueForNextRound,
        uint256 betPriceForNextRound
    );

    // Custom errors
    error AddressZero();
    error BetIsClosed();
    error ZeroAmountNotAllowed();
    error AlreadyProcessed();
    error CalledTooSoon();
    error TransferFailed();
    error InvalidBetValue();
    error maxBetValueNotAllowed();
    error AlreadyBet();

    // Constructor
    constructor(
        address _betTokenAddress,
        uint256 _betPrice,
        uint256 _blocksBetweenRound,
        uint256 _amountOfHashesToDetermineWinner,
        uint256 _maxBetValue,
        address _feeCollector
    ) {
        betTokenAddress = _betTokenAddress;
        blocksBetweenRound = _blocksBetweenRound;
        betPrice = _betPrice;
        targetBlock = block.number + blocksBetweenRound;
        feeCollector = _feeCollector;

        maxBetValueForNextRound = _maxBetValue; // Default max bet value
        maxBetValue = _maxBetValue; // Default current bet value
        amountOfHashesToDetermineWinner = _amountOfHashesToDetermineWinner;
    }

    // Allows users to donate to the prize pool
    function donate(uint256 amount) public {
        if (amount == 0) revert ZeroAmountNotAllowed();
        IERC20 betToken = IERC20(betTokenAddress);
        betToken.transferFrom(msg.sender, address(this), amount);
        poolPrize += amount;
        emit DonationReceived(msg.sender, amount);
    }

    // Places a bet on behalf of an account, only if the round is not yet closed and the bet is valid.
    function placeBet(uint24 _bet, address account) public whenNotPaused {
        // Validation checks
        if (account == address(0)) revert AddressZero();
        if (block.number >= targetBlock) revert BetIsClosed();
        if (_bet > maxBetValue) revert InvalidBetValue();
        if (hasBet[targetBlock][_bet][account]) revert AlreadyBet();

        // Transfer tokens from bettor to contract
        IERC20 betToken = IERC20(betTokenAddress);
        betToken.transferFrom(account, address(this), betPrice);

        // Calculate and accumulate fees
        uint256 fee = (betPrice * BET_FEE) / BASIS_POINTS;
        totalFees += fee;
        poolPrize += (betPrice - fee);

        // Store the bet information
        bets[targetBlock][_bet].push(account);
        hasBet[targetBlock][_bet][account] = true;

        emit BetPlaced(msg.sender, account, targetBlock, _bet);
    }

    // Determines the winning number by taking the blockhashes of `amountOfHashesToDetermineWinner` subsequent blocks starting from `baseTargetBlock`.
    function getWinningNumber(
        uint256 baseTargetBlock
    ) public view returns (uint24) {
        uint256 sum = 0;

        // Loop to calculate the sum based on multiple block hashes
        for (uint256 i = 0; i < amountOfHashesToDetermineWinner; i++) {
            bytes32 hash = blockhash(baseTargetBlock + i);

            // get the left half of the hash
            uint256 leftHalf = uint256(hash) >> 128;

            sum += leftHalf;
        }

        // adjust the result to be between 0 and maxBetValue
        uint24 winningNumber = uint24(sum % maxBetValue);

        return winningNumber;
    }

    // Resolves the lottery round by determining the winning number and distributing the prize pool accordingly.
    function resolveLottery() public {
        // Validation checks
        if (targetBlocksProcessed[targetBlock]) revert AlreadyProcessed();
        // we need to sum 2 in case the second attempt is needed
        if (block.number < targetBlock + amountOfHashesToDetermineWinner + 2)
            revert CalledTooSoon();

        // This is a fail-safe mechanism to reset the round and prevent a deadlock.
        // Although unlikely, if the function is not invoked within 256 blocks after the target block,
        // the contract could enter a deadlock state.
        // In such a case, the remaining prize pool will be carried over to the next round,
        // regardless of whether a winner could have been determined for the current round.
        if (block.number > targetBlock + 256) {
            resetForNextRound();
            return;
        }

        // Check if there is a winner
        uint24 winningNumber = getWinningNumber(targetBlock);
        address[] memory winners = bets[targetBlock][winningNumber];
        if (winners.length > 0) {
            uint256 winnerPrize = (poolPrize * FIRST_ROUND_WINNER_PERCENTAGE) /
                BASIS_POINTS;

            // Distribute the prize
            distributePrizes(winners, winnerPrize);

            // initialize the prize pool for the next round
            poolPrize = poolPrize - winnerPrize;

            emit PrizeClaimed(1, winners.length, winnerPrize);
        } else {
            // second attempt with targetBlock + 1
            winningNumber = getWinningNumber(targetBlock + 1);
            winners = bets[targetBlock][winningNumber];

            if (winners.length > 0) {
                uint256 winnerPrize = (poolPrize *
                    SECOND_ROUND_WINNER_PERCENTAGE) / BASIS_POINTS;

                // Distribute the prize
                distributePrizes(winners, winnerPrize);

                // initialize the prize pool for the next round
                poolPrize = poolPrize - winnerPrize;

                emit PrizeClaimed(2, winners.length, winnerPrize);
            }
        }

        resetForNextRound();
    }

    // Internal function to distribute prizes to winners
    function distributePrizes(
        address[] memory winners,
        uint256 prizeAmount
    ) internal {
        uint256 individualPrize = prizeAmount / winners.length;
        IERC20 token = IERC20(betTokenAddress);
        for (uint256 i = 0; i < winners.length; i++) {
            token.transfer(winners[i], individualPrize);
        }
    }

    // Internal function to reset for the next round
    function resetForNextRound() internal {
        targetBlocksProcessed[targetBlock] = true;
        targetBlock = block.number + blocksBetweenRound;
        betPrice = betPriceForNextRound;
        maxBetValue = maxBetValueForNextRound;
    }

    // Function to claim accumulated fees
    function claimFees() public onlyOwner {
        if (totalFees == 0) revert ZeroAmountNotAllowed();

        IERC20 betToken = IERC20(betTokenAddress);
        betToken.transfer(feeCollector, totalFees);
        totalFees = 0;
    }

    // Function to donate accumulated fees to the prize pool
    function donateFees() public onlyOwner {
        if (totalFees == 0) revert ZeroAmountNotAllowed();

        // Transfer the fees to the prize pool
        poolPrize += totalFees;
        // Reset the accumulated fees to zero
        totalFees = 0;

        emit DonationReceived(address(this), totalFees);
    }

    // Define a getter function for the `bettors` array
    function getBettors(
        uint256 _targetBlock,
        uint24 bet
    ) external view returns (address[] memory) {
        return bets[_targetBlock][bet];
    }

    // Function to get the current prices for the current round
    function getCurrentPrices() public view returns (uint256, uint256) {
        return (
            (poolPrize * FIRST_ROUND_WINNER_PERCENTAGE) / BASIS_POINTS,
            (poolPrize * SECOND_ROUND_WINNER_PERCENTAGE) / BASIS_POINTS
        );
    }

    // Function to set the maximum bet value for the next round
    function setNewConfig(
        uint256 _maxBetValueForNextRound,
        uint256 _betPriceForNextRound
    ) public onlyOwner {
        if (_maxBetValueForNextRound < 9 || _maxBetValueForNextRound > 99999)
            revert maxBetValueNotAllowed();
        if (_betPriceForNextRound == 0) revert ZeroAmountNotAllowed();

        maxBetValueForNextRound = _maxBetValueForNextRound;
        betPriceForNextRound = _betPriceForNextRound;

        emit newConfig(_maxBetValueForNextRound, _betPriceForNextRound);
    }
}
