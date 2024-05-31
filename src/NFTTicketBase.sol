// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { ERC1155 } from "../lib/openzeppelin-contracts/contracts/token/ERC1155/ERC1155.sol";
import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract NFTTicketBase is ERC1155("uri"), Ownable(msg.sender) {
    function initialize(string memory uri, bool _isTransferable, address _owner, string calldata _name, string calldata _symbol) public {
        require(initialized == false, "Already initialized");

        _transferOwnership(_owner);
        _setURI(uri);
        isTransferable = _isTransferable;
        name = _name;
        symbol = _symbol;
        initialized = true;
    }

    bool public initialized = false;

    string public name = "NFT Ticket";
    string public symbol = "TCKT";
    uint256 public nextTokenId = 1;
    address public depositContractAddr;
    bool public isTransferable;

    error NonTransferable();

    function setDepositContractAddr(address _depositContractAddr) public onlyOwner {
        depositContractAddr = _depositContractAddr;
    }

    function lotteryMint(address winner) public {
        require(msg.sender == depositContractAddr, "Only deposit contract can mint");

        _mint(winner, nextTokenId, 1, ""); // Mint 1 NFT to the winner
        nextTokenId++;
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public override {
        if(!isTransferable) {
            revert NonTransferable();
        }
        super.safeTransferFrom(from, to, id, amount, data);
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) public override {
        if(!isTransferable) {
            revert NonTransferable();
        }
        super.safeBatchTransferFrom(from, to, ids, amounts, data);
    }
}
