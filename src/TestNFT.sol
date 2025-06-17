// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.30;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract TestNFT is ERC721, Ownable {
    string private fixedTokenURI;
    uint256 private _nextTokenId;

    constructor(string memory fixedURI, address initialOwner)
        ERC721("TestNFT", "TNFT")
        Ownable(initialOwner)
    {
        fixedTokenURI = fixedURI;
    }

    function mint(address to) external {
        uint256 id = _nextTokenId++;
        _safeMint(to, id);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return fixedTokenURI;
    }
}
