// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TestNFT is ERC721, Ownable {
    string private _fixedTokenURI;
    uint256 private _nextTokenId;

    constructor(
        string memory fixedURI,
        address initialOwner
    ) ERC721("TestNFT", "TNFT") Ownable(initialOwner) {
        _fixedTokenURI = fixedURI;
    }

    function mint(address user) public {
        uint256 tokenId = _nextTokenId++;
        _mint(user, tokenId);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        _requireOwned(tokenId);
        return _fixedTokenURI;
    }

    function setFixedURI(string memory newURI) external onlyOwner {
        _fixedTokenURI = newURI;
    }
}
