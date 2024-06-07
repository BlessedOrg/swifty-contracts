// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { GelatoVRFConsumerBase } from "../lib/vrf-contracts/contracts/GelatoVRFConsumerBase.sol";
import { ERC2771Context } from "../lib/relay-context-contracts/contracts/vendor/ERC2771Context.sol";
import { Context } from "../lib/openzeppelin-contracts/contracts/utils/Context.sol";
import "src/vendor/StructsLibrary.sol";
import "src/interfaces/INFTLotteryTicket.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/ILotteryV2.sol";
import "src/interfaces/IAuctionV2.sol";

contract AuctionV1Base is GelatoVRFConsumerBase, Ownable(msg.sender), ERC2771Context(0xd8253782c45a12053594b9deB72d8e8aB2Fca54c) {
    function initialize(StructsLibrary.ILotteryBaseConfig memory config) public {
        require(initialized == false, "Already initialized");
        seller = config._blessedOperator;
        operatorAddr = config._gelatoVrfOperator;
        _transferOwnership(config._owner);
        totalNumberOfTickets = config._ticketAmount;
        numberOfTickets = config._ticketPrice;
        prevRoundTicketsAmount = config._ticketPrice;
        minimumDepositAmount = config._ticketPrice;
        currentPrice = config._ticketPrice;
        initialPrice = config._ticketPrice;
        usdcContractAddr = config._usdcContractAddr;
        multisigWalletAddress = config._multisigWalletAddress;
        lotteryV2Addr = config._prevPhaseContractAddr;

        initialized = true;
    }

    bool public initialized = false;

    enum LotteryState {
        NOT_STARTED,
        ACTIVE,
        ENDED,
        VRF_REQUESTED,
        VRF_COMPLETED
    }

    LotteryState public lotteryState;

    address public multisigWalletAddress;
    address public seller;
    address public operatorAddr;

    uint256 public minimumDepositAmount;
    uint256 public currentPrice;
    uint256 public initialPrice;
    uint256 public prevRoundDeposits = 1;
    uint256 public prevRoundTicketsAmount = 1;
    uint256 public increasePriceStep = 5;
    uint256 public numberOfTickets;
    uint256 public totalNumberOfTickets;
    uint256 public randomNumber;
    address[] public eligibleParticipants;
    mapping(address => bool) public hasMinted;

    struct Round {
        uint256 number;
        uint256 finishAt;
        uint256 numberOfTickets;
        bool lotteryStarted;
        bool winnersSelected;
    }
    mapping(uint256 => Round) public rounds;
    uint256 public roundCounter;

    mapping(address => uint256) public deposits;
    mapping(address => bool) public winners;
    mapping(address => bool) public operators;
    address[] public winnerAddresses;
    address[] private participants;

    address public nftContractAddr;
    address public usdcContractAddr;
    address public lotteryV2Addr;

    event LotteryStarted();
    event WinnerSelected(address indexed winner);
    event LotteryEnded();
    event RandomRequested(address indexed requester);
    event RandomFullfiled(uint256 number);

    modifier onlySeller() {
        require(_msgSender() == seller, "Only seller can call this function");
        _;
    }

    modifier onlyOperator() {
        // operator = seller or owner or specified address
        require(_msgSender() == seller || _msgSender() == owner() || operators[_msgSender()], "Only operator can call this function");
        _;
    }    

    modifier lotteryNotStarted() {
        require(lotteryState == LotteryState.NOT_STARTED || lotteryState == LotteryState.ENDED, "Lottery is in active state");
        _;
    }

    modifier lotteryStarted() {
        require(lotteryState == LotteryState.ACTIVE, "Lottery is not active");
        _;
    }

    modifier lotteryEnded() {
        require(lotteryState == LotteryState.ENDED, "Lottery is not ended yet");
        _;
    }

    modifier whenLotteryNotActive() {
        require(lotteryState != LotteryState.ACTIVE, "Lottery is currently active");
        _;
    }

    function setSeller(address _seller) external onlySeller {
        seller = _seller;
    }

    function _msgSender() internal view override(ERC2771Context, Context) returns (address sender) {
        sender = ERC2771Context._msgSender();
    }

    function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata) {
        return ERC2771Context._msgData();
    }    

    function _operator() internal view override returns (address) {
        return operatorAddr;
    }

    function deposit(uint256 amount) public payable {
        require(!isWinner(_msgSender()), "Winners cannot deposit");
        require(usdcContractAddr != address(0), "USDC contract address not set");
        require(amount > 0, "No funds sent");
        require(
            IERC20(usdcContractAddr).allowance(_msgSender(), address(this)) >= amount, 
            "Insufficient allowance"
        );

        IERC20(usdcContractAddr).transferFrom(_msgSender(), address(this), amount);
        
        if(deposits[_msgSender()] == 0) {
            participants.push(_msgSender());
        }
        deposits[_msgSender()] += amount;
        prevRoundDeposits += 1;
    }

    function getParticipants() public view returns (address[] memory) {
        return participants;
    }

    function getEligibleParticipants() public view returns (address[] memory) {
        return eligibleParticipants;
    }

    function setMultisigWalletAddress(address _multisigWalletAddress) public onlyOwner {
        multisigWalletAddress = _multisigWalletAddress;
    }

    function setOperator(address _operatorAddr, bool _flag) public onlyOwner {
        operators[_operatorAddr] = _flag;
    }     

    function setPriceStep(uint256 _increasePriceStep) public onlySeller {
        increasePriceStep = _increasePriceStep;
    }   

    function setupNewRound(uint256 _finishAt, uint256 _numberOfTickets) public onlyOperator {
        require(_numberOfTickets <= totalNumberOfTickets, "Tickets per round cannot be higher than total number of tickets in AuctionV1");
        uint256 newPrice = 0;

        if (prevRoundDeposits >= numberOfTickets) {
            // higher demand than supply, increase price
            newPrice = currentPrice + increasePriceStep * (prevRoundDeposits / prevRoundTicketsAmount);
        } else {
            // lower demand than supply, decrease price
            uint256 decreaseAmount = increasePriceStep * (1 - prevRoundDeposits / prevRoundTicketsAmount);
            if (currentPrice > decreaseAmount) {
                newPrice = currentPrice - decreaseAmount;
            } else {
                newPrice = initialPrice;
            }
        }
        currentPrice = newPrice;
        prevRoundDeposits = 0;
        numberOfTickets = _numberOfTickets;
        prevRoundTicketsAmount = _numberOfTickets;
        totalNumberOfTickets -= _numberOfTickets;

        rounds[roundCounter] = Round({
            number: roundCounter,
            finishAt: _finishAt,
            numberOfTickets: _numberOfTickets,
            lotteryStarted: false,
            winnersSelected: false
        });

        roundCounter++;
    }

    function setNftContractAddr(address _nftContractAddr) public onlyOwner {
        nftContractAddr = _nftContractAddr;
    }

    function changeLotteryState(LotteryState _newState) public onlySeller {
        lotteryState = _newState;
    }

    function isWinner(address _participant) public view returns (bool) {
        return winners[_participant];
    }

    function getWinners() public view returns (address[] memory) {
        return winnerAddresses;
    }

    function setWinner(address _winner) public onlySeller {
        winners[_winner] = true;
        winnerAddresses.push(_winner);
    }

    function buyerWithdraw() public whenLotteryNotActive {
        require(!winners[_msgSender()], "Winners cannot withdraw");

        uint256 amount = deposits[_msgSender()];
        require(amount > 0, "No funds to withdraw");

        deposits[_msgSender()] = 0;
        IERC20(usdcContractAddr).transfer(_msgSender(), amount);
    }

    function sellerWithdraw() public onlySeller() {
        require(lotteryState == LotteryState.ENDED, "Lottery not ended");

        uint256 totalAmount = 0;

        for (uint256 i = 0; i < winnerAddresses.length; i++) {
            address winner = winnerAddresses[i];
            totalAmount += deposits[winner];
            deposits[winner] = 0; // Prevent double withdrawal
        }

        uint256 protocolTax = (totalAmount * 5) / 100; // 5% tax
        uint256 amountToSeller = totalAmount - protocolTax;

        IERC20(usdcContractAddr).transfer(multisigWalletAddress, protocolTax);
        IERC20(usdcContractAddr).transfer(seller, amountToSeller);
    }

    function requestRandomness() external onlySeller {
        _requestRandomness(abi.encode(_msgSender()));
        emit RandomRequested(_msgSender());
    } 

    function _fulfillRandomness(uint256 randomness, uint256, bytes memory) internal override {
        randomNumber = randomness;
        emit RandomFullfiled(randomness);
    }        

    function getRandomNumber () public view returns (uint256) {
        // it's used as a mockup for tests
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, _msgSender()))); 
    }

    function selectWinners() external onlySeller {
        require(numberOfTickets > 0, "No tickets left to allocate");
        lotteryState = LotteryState.ACTIVE;
        checkEligibleParticipants();

        if(numberOfTickets >= eligibleParticipants.length) {
            // If demand is less than or equal to supply, everyone wins
            for (uint256 i = 0; i < eligibleParticipants.length; i++) {
                address selectedWinner = eligibleParticipants[i];
                if (!isWinner(selectedWinner)) {
                    setWinner(selectedWinner);
                    emit WinnerSelected(selectedWinner);
                }
            }
            // Clear the participants list since all are winners
            delete eligibleParticipants;
            numberOfTickets = 0;
        } else {
            // Shuffle the array of participants
            for (uint j = 0; j < eligibleParticipants.length; j++) {
                uint n = j + randomNumber % (eligibleParticipants.length - j);
                address temp = eligibleParticipants[n];
                eligibleParticipants[n] = eligibleParticipants[j];
                eligibleParticipants[j] = temp;
            }

            // Select the first `numberOfTickets` winners
            for (uint256 i = 0; i < numberOfTickets; i++) {
                address selectedWinner = eligibleParticipants[i];
                if (!isWinner(selectedWinner)) {
                    setWinner(selectedWinner);
                    emit WinnerSelected(selectedWinner);
                }
            }

            // Remove the winners from the participants list by shifting non-winners up
            uint256 shiftIndex = 0;
            for (uint256 i = numberOfTickets; i < eligibleParticipants.length; i++) {
                eligibleParticipants[shiftIndex] = eligibleParticipants[i];
                shiftIndex++;
            }
            for (uint256 i = shiftIndex; i < eligibleParticipants.length; i++) {
                eligibleParticipants.pop();
            }

            numberOfTickets = 0;
        }

        if (totalNumberOfTickets == 0) {
            emit LotteryEnded();
        }
        rounds[roundCounter - 1].winnersSelected = true;
        lotteryState = LotteryState.NOT_STARTED;
    }

    function setCurrentPrice(uint256 _amount) public onlySeller {
      if(initialPrice == 0) {
        initialPrice = _amount;
      }
      currentPrice = _amount;
    }

    function setNumberOfTickets(uint256 _numberOfTickets) public onlySeller {
        require(_numberOfTickets > 0, "Number of tickets must be greater than zero");
        numberOfTickets = _numberOfTickets;
        prevRoundTicketsAmount = _numberOfTickets;
    }

    function startLottery() public onlySeller lotteryNotStarted {
        changeLotteryState(LotteryState.ACTIVE);
        checkEligibleParticipants();
        rounds[roundCounter].lotteryStarted = true;
    }

    function endLottery() public onlySeller {
        changeLotteryState(LotteryState.ENDED);
        // Additional logic for ending the lottery
        // Process winners, mint NFT tickets, etc.
    }

    function getDepositedAmount(address participant) external view returns (uint256) {
        return deposits[participant];
    }

    // Function to check and mark eligible participants
    function checkEligibleParticipants() internal {
        delete eligibleParticipants;
        for (uint256 i = 0; i < participants.length; i++) {
            uint256 depositedAmount = deposits[participants[i]];
            if (depositedAmount >= currentPrice) {
                // Mark this participant as eligible for the lottery
                if (!isWinner(participants[i])) {
                  eligibleParticipants.push(participants[i]);
                }
            }
        }
    }

    function removeParticipant(uint256 index) internal {
        require(index < eligibleParticipants.length, "Index out of bounds");

        // If the winner is not the last element, swap it with the last element
        if (index < eligibleParticipants.length - 1) {
            eligibleParticipants[index] = eligibleParticipants[eligibleParticipants.length - 1];
        }

        // Remove the last element (now the winner)
        eligibleParticipants.pop();
    }

    function isParticipantEligible(address participant) public view returns (bool) {
        for (uint256 i = 0; i < eligibleParticipants.length; i++) {
            if (eligibleParticipants[i] == participant) {
                return true;
            }
        }
        return false;
    }

    function mintMyNFT() public {
        require(isWinner(_msgSender()), "Caller is not a winner");
        require(!hasMinted[_msgSender()], "NFT already minted");
        INFTLotteryTicket(nftContractAddr).lotteryMint(_msgSender());
        hasMinted[_msgSender()] = true;
    }

    function setUsdcContractAddr(address _usdcContractAddr) public onlyOwner {
        usdcContractAddr = _usdcContractAddr;
    }

    function setLotteryV2Addr(address _lotteryV2Addr) public onlySeller {
        lotteryV2Addr = _lotteryV2Addr;
    }    

    function transferDeposit(address _participant, uint256 _amount) public {
        require(lotteryV2Addr == _msgSender(), "Only whitelisted may call this function");

        if(deposits[_msgSender()] == 0) {
            participants.push(_participant);
        }
        deposits[_participant] += _amount;
        prevRoundDeposits += 1;
    }

    function transferNonWinnerBids(address destinationAddr) public onlySeller {
        for(uint256 i = 0; i < participants.length; i++) {
            uint256 currentDeposit = deposits[participants[i]];
            deposits[participants[i]] = 0;
            IERC20(usdcContractAddr).transfer(destinationAddr, currentDeposit);
            IAuctionV2(destinationAddr).transferDeposit(participants[i], currentDeposit);

            if (i < participants.length - 1) {
                participants[i] = participants[participants.length - 1];
            }
            participants.pop();
        }
    }
}
