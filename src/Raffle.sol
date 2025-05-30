// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import {console} from "forge-std/console.sol";
/**
 * @title A sample Raffle contract
 * @author segroegg
 * @notice This contract is for creating a simple raffle
 * @dev Implements Chainlink VRFv2.5
 */
// This is called natspec, it is a way to document your code
contract Raffle is VRFConsumerBaseV2Plus {
    /* Errors */
    error Raffle__SendMoreToEnterRaffle();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(uint256 balance, uint256 playersLength, uint256 raffleState);

    /* Type declarations */
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    /*   State variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3; // How many blocks to wait before fulfilling the request
    uint32 private constant numWords = 1;
    uint256 private immutable i_entraceFee;

    // @dev The duration of the lottery in seconds
    uint256 private immutable i_interval;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;

    // What data structure should we use ? How to keep track of all players ?
    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /* Events */
    event RaffleEntered(address indexed player);
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane, // keyhash
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entraceFee = entranceFee;
        i_interval = interval;
        i_keyHash = gasLane; // keyhash is the gas lane, it is used to pay for the VRF request
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
        // s_vrfCoordinator.blabla // we can work with s_vrfCoordinator because we inherit from VRFConsumerBaseV2Plus
    }

    function enterRaffle() external payable {
        // require(msg.value >= i_entraceFee, "Not enough ETH sent !"); // takes a lot more gas because we need to store the string
        // require(msg.value >= i_entraceFee, SendMoreToEnterRaffle()); // works on newer versions of solidity
        if (msg.value < i_entraceFee) {
            revert Raffle__SendMoreToEnterRaffle();
        }

        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));

        // emit an event whenever we update a storage variable
        // 1. Makes migration easier
        // 2. Makes front end "indexing" easier
        // smart contracts cant access logs
        // indexed keywork : parameters that are much easier to search for and to query than non-indexed parameters
        // non-indexed one are harder to search for because they get abi-encoded and you have to know the abi to decode them
        emit RaffleEntered(msg.sender);
    }

    // When should the winner be picked ?
    /**
     * @dev This is the function that the Chainlink nodes will call to see
     * if the lottery is ready to have a winner picked.
     * The following should be true in order for upkeepNeeded to be true:
     * 1. The time interval has passed between raffle runs
     * 2. The lotter is open 
     * 3. The contract has ETH
     * 4. Implicitly, your subscription has LINK
     * @param - ignored 
     * @return upkeepNeeded - true if it's time to restart the lottery
     * @return - ignored
     */
    function checkUpkeep(bytes memory /* checkData */) public view
        returns (bool upkeepNeeded, bytes memory /* performData */) // we are not going to use performData in this example
        // by initializing variable in the returns clause, we don't need to declare them in the function body
        // it will automatically return the value of upkeepNeeded. No need to add the return statement. Cool solidity syntaxic sugar
    {
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >= i_interval);
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;

        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, ""); // returning null for performData, we don't need it in this example
    }

    // 1. Get a random number
    // 2. Use random number to pick a player
    // 3. Be automatically called -> using chainlink automation to quick off, lottery will just run programmatically without us ever having to interact with it
    function pickWinner(bytes calldata /* performData */) external { // we transformed our pickWinner function to make it the equivalent of a "performUpkeep" function
        // check to see if enough time has passed
        (bool upkeepNeed,) = checkUpkeep("");
        if (!upkeepNeed) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }

        s_raffleState = RaffleState.CALCULATING;

        // Get our random number
        // 1. Request RNG

        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_keyHash, // gas price to work with chainlink node
                subId: i_subscriptionId, // how we fund the oracle gas to work with chainlink VRF
                requestConfirmations: REQUEST_CONFIRMATIONS, // how many blocks we should wait for the chainlink node to give us the random number
                callbackGasLimit: i_callbackGasLimit, // so that we dont spend to much gas on the callback
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });

        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);
    }

    function performUpkeep(bytes calldata /* performData */) external { // we transformed our pickWinner function to make it the equivalent of a "performUpkeep" function
        // check to see if enough time has passed
        (bool upkeepNeed,) = checkUpkeep("");
        if (!upkeepNeed) {
            revert Raffle__UpkeepNotNeeded(address(this).balance, s_players.length, uint256(s_raffleState));
        }

        s_raffleState = RaffleState.CALCULATING;

        // Get our random number
        // 1. Request RNG

        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_keyHash, // gas price to work with chainlink node
                subId: i_subscriptionId, // how we fund the oracle gas to work with chainlink VRF
                requestConfirmations: REQUEST_CONFIRMATIONS, // how many blocks we should wait for the chainlink node to give us the random number
                callbackGasLimit: i_callbackGasLimit, // so that we dont spend to much gas on the callback
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });

        uint256 requestId = s_vrfCoordinator.requestRandomWords(request);

        emit RequestedRaffleWinner(requestId);
    }

    // CEI : Checks, Effects, Interactions
    // 2. Get RNG
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords /* randomword => random number */
    )
        internal
        override
    /* when we inherit abstract constract, we should override the virtual functions */ {
        // s_player = 10
        // rng = 12
        // 12 % 10 = 2
        // 7823648726487263487628374682763487628473687 % 10 = 9
        // Checks (none here) starting with checks is more gas efficient, because we revert earlier and don't do a bunch of work
        // require(), conditionals

        // Effects (internal contract state changes)
        uint256 indexOfWinner = randomWords[0] % s_players.length; // get a random index from the players array
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;

        s_players = new address payable[](0); // reset the players array
        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
        emit WinnerPicked(recentWinner);

        // Interactions (External Contract interactions)
        (bool success, ) = recentWinner.call{value: address(this).balance}(""); // transfer the balance to the winner
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /* Getter functions */
    function getEntranceFee() public view returns (uint256) {
        return i_entraceFee;
    }

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}
