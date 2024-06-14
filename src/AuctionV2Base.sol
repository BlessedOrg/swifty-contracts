// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { ERC2771Context } from "../lib/relay-context-contracts/contracts/vendor/ERC2771Context.sol";
import { Context } from "../lib/openzeppelin-contracts/contracts/utils/Context.sol";
import "src/vendor/StructsLibrary.sol";
import "src/interfaces/INFTLotteryTicket.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/ILotteryV2.sol";

contract AuctionV2Base is Ownable(msg.sender), ERC2771Context(0xd8253782c45a12053594b9deB72d8e8aB2Fca54c) {
    function initialize(StructsLibrary.IAuctionBaseConfig memory config) public {
        require(initialized == false, "Already initialized");
        seller = config._seller;
        _transferOwnership(config._owner);
        numberOfTickets = config._ticketAmount;
        minimumDepositAmount = config._ticketPrice;
        initialPrice = config._ticketPrice;
        usdcContractAddr = config._usdcContractAddr;
        multisigWalletAddress = config._multisigWalletAddress;
        auctionV1Addr = config._prevPhaseContractAddr;

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

    struct Deposit {
      uint256 amount;
      uint256 timestamp;
      bool isWinner;
    }

    address public multisigWalletAddress;
    address public seller;

    uint256 public minimumDepositAmount;
    uint256 public initialPrice;
    uint256 public numberOfTickets;
    mapping(address => bool) public hasMinted;

    mapping(address => Deposit) public deposits;
    mapping(address => bool) public winners;
    mapping(address => bool) public operators;
    address[] public winnerAddresses;
    address[] private participants;

    address public nftContractAddr;
    address public usdcContractAddr;
    address public auctionV1Addr;

    event LotteryStarted();
    event WinnerSelected(address indexed winner);
    event LotteryEnded();

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

    modifier hasNotMinted() {
        require(!hasMinted[_msgSender()], "NFT already minted");
        _;
    }

    modifier whenLotteryNotActive() {
        require(lotteryState != LotteryState.ACTIVE, "Lottery is currently active");
        _;
    }

    function _msgSender() internal view override(ERC2771Context, Context)
        returns (address sender) {
        sender = ERC2771Context._msgSender();
    }

    function _msgData() internal view override(ERC2771Context, Context)
        returns (bytes calldata) {
        return ERC2771Context._msgData();
    }

    function isParticipant(address _participant) public view returns (bool) {
        for (uint i = 0; i < participants.length; i++) {
            if (participants[i] == _participant) {
                return true;
            }
        }
        return false;
    }    

    function deposit(uint256 amount) public payable lotteryStarted {
        require(!isWinner(_msgSender()), "Winners cannot deposit");
        require(usdcContractAddr != address(0), "USDC contract address not set");
        require(amount >= initialPrice, "Insufficient funds sent");
        require(amount > 0, "No funds sent");
        require(IERC20(usdcContractAddr).allowance(_msgSender(), address(this)) >= amount, "Insufficient allowance");

        IERC20(usdcContractAddr).transferFrom(_msgSender(), address(this), amount);
        
        if(isParticipant(_msgSender())) {
            deposits[_msgSender()].amount += amount;
        } else {
            deposits[_msgSender()] = Deposit(amount, block.timestamp, false);
            participants.push(_msgSender());
        }
    }

    function setMultisigWalletAddress(address _multisigWalletAddress) public onlyOwner {
        multisigWalletAddress = _multisigWalletAddress;
    }

    function setOperator(address _operator, bool _flag) public onlyOwner {
        operators[_operator] = _flag;
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

    function getParticipants() public view returns (address[] memory) {
        return participants;
    }

    function setWinner(address _winner) public onlySeller {
        winners[_winner] = true;
        winnerAddresses.push(_winner);
        deposits[_winner].isWinner = true;
    }

    function buyerWithdraw() public whenLotteryNotActive {
        require(!winners[_msgSender()], "Winners cannot withdraw");

        uint256 amount = deposits[_msgSender()].amount;
        require(amount > 0, "No funds to withdraw");

        deposits[_msgSender()].amount = 0;
        IERC20(usdcContractAddr).transfer(_msgSender(), amount);
    }

    function sellerWithdraw() public onlySeller() {
        require(lotteryState == LotteryState.ENDED, "Lottery not ended");

        uint256 totalAmount = 0;

        for (uint256 i = 0; i < winnerAddresses.length; i++) {
            address winner = winnerAddresses[i];
            totalAmount += deposits[winner].amount;
            deposits[winner].amount = 0; // Prevent double withdrawal
        }

        uint256 protocolTax = (totalAmount * 5) / 100; // 5% tax
        uint256 amountToSeller = totalAmount - protocolTax;

        IERC20(usdcContractAddr).transfer(multisigWalletAddress, protocolTax);
        IERC20(usdcContractAddr).transfer(seller, amountToSeller);
    }

    // sort participants by deposit amount DESC
    function sortDepositsDesc() public onlySeller {
      for (uint256 i = 0; i < participants.length; i++) {
        for (uint256 j = i + 1; j < participants.length; j++) {
          if (deposits[participants[i]].amount < deposits[participants[j]].amount) {
            address temp = participants[i];
            participants[i] = participants[j];
            participants[j] = temp;
          }
        }
      }
    }

    function selectWinners() external onlySeller {
        require(numberOfTickets > 0, "No tickets left to allocate");

        if(numberOfTickets >= participants.length) {
            // less demand than supply, no need for lottery. Everybody wins!
            for (uint256 i = 0; i < participants.length; i++) {
                address selectedWinner = participants[i];

                if (!isWinner(selectedWinner)) {
                    setWinner(selectedWinner);
                    emit WinnerSelected(selectedWinner);
                }
            }
        } else {
            sortDepositsDesc();
            uint256 lowestWinDeposit = deposits[participants[numberOfTickets - 1]].amount;

            // take the first n winners
            for (uint256 i = 0; i < numberOfTickets; i++) {
                if(deposits[participants[i]].amount >= lowestWinDeposit) {
                  address selectedWinner = participants[i];

                  if (!isWinner(selectedWinner)) {
                      setWinner(selectedWinner);
                      emit WinnerSelected(selectedWinner);
                  }
                }
            }
        }
        emit LotteryEnded();
    }

    function setInitPrice(uint256 _amount) public onlySeller {
      if(initialPrice == 0) {
        initialPrice = _amount;
      }
    }

    function setNumberOfTickets(uint256 _numberOfTickets) public onlySeller {
        require(_numberOfTickets > 0, "Number of tickets must be greater than zero");
        numberOfTickets = _numberOfTickets;
    }

    function startLottery() public onlySeller lotteryNotStarted {
        changeLotteryState(LotteryState.ACTIVE);
    }

    function endLottery() public onlySeller {
        changeLotteryState(LotteryState.ENDED);
        // Additional logic for ending the lottery
        // Process winners, mint NFT tickets, etc.
    }

    function getDepositedAmount(address participant) external view returns (uint256) {
        return deposits[participant].amount;
    }

    function mintMyNFT() public hasNotMinted {
        require(numberOfTickets > 0, "No tickets left to allocate");
        require(isWinner(_msgSender()), "Caller is not a winner");
        uint256 remainingBalance = deposits[_msgSender()] - minimumDepositAmount;
        deposits[_msgSender()] = 0;
        hasMinted[_msgSender()] = true;
        INFTLotteryTicket(nftContractAddr).lotteryMint(_msgSender());
        numberOfTickets--;
        if (remainingBalance > 0) {
            IERC20(usdcContractAddr).transfer(_msgSender(), remainingBalance);
        }
    }

    function setUsdcContractAddr(address _usdcContractAddr) public onlyOwner {
        usdcContractAddr = _usdcContractAddr;
    }

    function setAuctionV1Addr(address _auctionV1Addr) public onlyOperator() {
        auctionV1Addr = _auctionV1Addr;
    }

    function transferDeposit(address _participant, uint256 _amount) public {
        require(auctionV1Addr == _msgSender(), "Only whitelisted may call this function");

        if(isParticipant(_participant)) {
            deposits[_participant].amount += _amount;
        } else {
            deposits[_participant] = Deposit(_amount, block.timestamp, false);
            participants.push(_participant);
        }
    }    
}
