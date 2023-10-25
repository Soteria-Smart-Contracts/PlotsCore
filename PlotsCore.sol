// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

contract PlotsCore{
    address[] public ListedCollections;


    mapping(address => bool) public Admins;

    mapping(address => uint256[]) public AvailableTokensByCollection;
    mapping(address => mapping(uint256 => uint256)) public AvailableTokensByCollectionIndex;
    
    modifier OnlyAdmin(){
        require(Admins[msg.sender], "Only Admin");
        _;
    }

    constructor(address [])




}
