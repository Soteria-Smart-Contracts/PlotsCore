console.log('merklegen.js loaded');


let whitelistAddresses = [
  {
    "address": "0x04ab4c210f4d9814cd12a8804d249ec387f8ec61",
    "points": 1367789
  },
  {
    "address": "0x5186fc0017a983c51b3845f0ed7800a4c23ad0b0",
    "points": 414469
  },
  {
    "address": "0x72703b554a7089f93ff1fc6cc6c0e623900a7b80",
    "points": 381791
  },
  {
    "address": "0xb0cbf149ba9e7d0efb63235a08768a7b63f0652f",
    "points": 322092
  },
  {
    "address": "0xfc60750c91fd4090151ed42c5e88ff94e25e3f40",
    "points": 270608
  }
];

//convert the whitelistAddresses to an array of addresses with the points number appended to the address end
ClaimantAddresses = data1.map((address) => {
  return address.address + address.points;
});

WhitelistAddresses = data2.map((address) => {
  return address.address;
}

const leafNodes = whitelistAddresses.map(addr => keccak256(addr));
let merkleTree = new MerkleTree(leafNodes, keccak256, { sortPairs: true});

//output the merkle tree in a copy-pasteable format
merkleTree = JSON.stringify(merkleTree, null, 2);
console.log(merkleTree);

//convert the merkle tree back to a MerkleTree object using the MerkleTree string
merkleTree = new MerkleTree(JSON.parse(merkleTree), keccak256, { sortPairs: true});

// Get root hash of the `merkleeTree` in hexadecimal format (0x)
// Print out the Entire Merkle Tree.
const rootHash = merkleTree.getRoot();
const rootHashBytes32 = '0x' + merkleTree.getRoot().toString('hex');
console.log("Root Hash: ", rootHashBytes32);

// ***** ***** ***** ***** ***** ***** ***** ***** // 

// Function to generate hex proof for a claiming address
function generateHexProof(claimingAddress) {
  // `getHexProof` returns the neighbour leaf and all parent nodes hashes that will

  //convert the claimingAddress to an address with the points number appended to the address end and then hash it
  claimingAddress = keccak256(claimingAddress);
  // be required to derive the Merkle Trees root hash.
  const hexProof = merkleTree.getHexProof(claimingAddress);

  // ✅ - ❌: Verify if claiming address is in the merkle tree or not.
  // This would be implemented in your Solidity Smart Contract
  const isAddressInTree = merkleTree.verify(hexProof, claimingAddress, rootHash);

  return {
    hexProof: hexProof,
    isAddressInTree: isAddressInTree
  };
}