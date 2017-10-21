# Early Bird Presale, Presale, Early Bird Crowdsale, Crowdsale Deployment steps

1) When deploying the sale contract to the blockchain pass in two pieces of information:
	* Address of the token contract
	* Address of a wallet to store funds raised during the sale

2) Once the contract is deployed on the blockchain, send the tokens to be sold during the sale to the contract address.

3) After the tokens are deposited, run the 'launch contract' functions, which will activate the presale, and allow ethereum to be sent.

4) When you want to allow people to withdraw their tokens or to push the tokens to the backers, run the 'enable withdrawals' function