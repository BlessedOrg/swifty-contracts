// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "src/interfaces/INFTLotteryTicket.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/ILotteryV2.sol";

contract AuctionV2 is Ownable {
    constructor(address _seller)
    Ownable(msg.sender) {
        seller = _seller;
    }

    enum LotteryState {
        NOT_STARTED,
        ACTIVE,
        ENDED,
        VRF_REQUESTED,
        VRF_COMPLETED
    }

    struct Deposit {
      uint256 amount;
      uint256 timestamp;
      bool isWinner;
    }

    LotteryState public lotteryState;

    address public multisigWalletAddress;
    address public seller;

    uint256 public initialPrice;
    uint256 public numberOfTickets;
    mapping(address => bool) public hasMinted;

    mapping(address => Deposit) public deposits;
    mapping(address => bool) public winners;
    mapping(address => bool) public operators;
    address[] public winnerAddresses;
    address[] public participants;

    address public nftContractAddr;
    address public usdcContractAddr;

    uint256 public finishAt;

    event LotteryStarted();
    event WinnerSelected(address indexed winner);
    event LotteryEnded();

    modifier onlySeller() {
        require(msg.sender == seller, "Only seller can call this function");
        _;
    }

    modifier onlyOperator() {
        // operator = seller or owner or specified address
        require(msg.sender == seller || msg.sender == owner() || operators[msg.sender], "Only operator can call this function");
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
        require(!hasMinted[msg.sender], "NFT already minted");
        _;
    }

    modifier whenLotteryNotActive() {
        require(lotteryState != LotteryState.ACTIVE, "Lottery is currently active");
        _;
    }

    function isParticipant(address _participant) public view returns (bool) {
        for (uint i = 0; i < participants.length; i++) {
            if (participants[i] == _participant) {
                return true;
            }
        }
        return false;
    }    

    function deposit(uint256 amount) public payable {
        require(!isWinner(msg.sender), "Winners cannot deposit");
        require(finishAt > block.timestamp, "Deposits are not possible anymore");
        require(usdcContractAddr != address(0), "USDC contract address not set");
        require(amount >= initialPrice, "Insufficient funds sent");
        require(amount > 0, "No funds sent");
        require(
            IERC20(usdcContractAddr).allowance(msg.sender, address(this)) >= amount, 
            "Insufficient allowance"
        );

        IERC20(usdcContractAddr).transferFrom(msg.sender, address(this), amount);
        
        if(isParticipant(msg.sender)) {
            deposits[msg.sender].amount += amount;
        } else {
            deposits[msg.sender] = Deposit(amount, block.timestamp, false);
            participants.push(msg.sender);
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

    function setWinner(address _winner) public onlySeller {
        winners[_winner] = true;
        winnerAddresses.push(_winner);
        deposits[_winner].isWinner = true;
    }

    function buyerWithdraw() public whenLotteryNotActive {
        require(!winners[msg.sender], "Winners cannot withdraw");

        uint256 amount = deposits[msg.sender].amount;
        require(amount > 0, "No funds to withdraw");

        deposits[msg.sender].amount = 0;
        IERC20(usdcContractAddr).transfer(msg.sender, amount);
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
            for (uint256 i = 0; i < participants.length; i++) {
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

    function mintMyNFT() public hasNotMinted lotteryEnded {
        require(numberOfTickets > 0, "No tickets left to allocate");
        require(isWinner(msg.sender), "Caller is not a winner");

        hasMinted[msg.sender] = true;
        INFTLotteryTicket(nftContractAddr).lotteryMint(msg.sender);
        numberOfTickets--;
    }

    function setUsdcContractAddr(address _usdcContractAddr) public onlyOwner {
        usdcContractAddr = _usdcContractAddr;
    }

    function setFinishAt(uint _finishAt) public onlyOperator() {
        finishAt = _finishAt;
    }
}
