<div style="text-align: center;">
  <img width="300" alt="image" src="image/Glifio.png">
</div>


# Questions

##  Communications

- Who's going to be the main point of contact during the audit?
Jonathan Schwartz 
Telegram: @jpschwartz

- What should be the main comms channel with the development team?
Telegram

- Should we share drafts of potentially severe issues in advance? Where? With whom?
Yes, can share immediately with Jonathan

- Would you rather have sync meetings during the course of the audit to share progress?
No async is fine unless we need a call to discuss a specific issue in more detail - can do ad hoc


##  Documentation

- What's the available documentation? Where can we find it?
The source code is well commented and I will walk the auditors through the code and architecture

- Is the documentation up-to-date?
Yes

- Does the documentation match the version of the system about to be audited?
Yes


##  Prior security work

- Is this the first audit you're getting? If not, can you share who else audited it? Can we read previous audit reports?
We've had 2 security researchers help review the code and write fuzz tests + formal verification

- Are you planning to formally verify parts of the system?
Yes

- Does your team run security-oriented tooling? Which? How (manually, CI, etc)?
Yes - forge fuzz tests, Echidna + Medusa


##  Project

- Is it possible to schedule a walkthrough of the code base with a developer? 45 min should do.
Yes

- Is the code forked from a well-known project? Or at least heavily inspired? Not necessarily as a whole – perhaps some parts. If so, what features did you add / remove? Why?
No

- Is the code already in production? If so, how should we proceed if we find a critical vulnerability?
No - report to Jonathan Schwartz

- If the code isn't deployed, is it *about* to be deployed? When?
Yes, probably july/august

- To which chains are you deploying it?
FEVM Filecoin

- Is the code frozen? Or do you expect changes during the audit? Where? When? Should we periodically incorporate those changes?
There may be additional view functions added, but no core logic should be changed. 

- What are the most sensitive parts of the codebase? What are you most fearful of?
I'm not fearful of any parts of the code. I'm concerned that we're forgetting helpful functionality to provide better UX. Currently investigating issues with imprecision.


- What parts of the project would you consider the least tested?
Complex scenario analysis.


- What parts of the code where the most difficult to tackle?
Getting the math and precision precision 

- Where did you make the most changes throughout the development process?
The core math aspects, mostly in `updateAccounting` and the various view functions

- Are there any attack vectors you've already thought of? Are they documented? How's the code preventing them?
I don't see any hack vectors currently, only potential annoying UX blockers and bad upgradeability.

- What are the most relevant integrations to consider? (oracles, DEXs, tokens, bridges, etc). Can we assume these external elements to work as documented?
Filecoin FEVM has unique precompiles, so we use certain libraries to call FEVM precompiles, which are not standard on EVM. The FEVM addres space also has some unique quirks, however these things have been audited and used in production for over a year.

There are no external integration besides the GLIF token, these external elements work as documented.

- Are you implementing and/or following any known ERC?
Not in this contract

- Are you using well-known libraries as dependencies? Which ones? Any specific reason why you decided to use X instead of Y?
We're using Open Zeppelin libraries where applicable. We also use our own fork of the Open Zeppelin Ownable contract that handles Filecoin native addresses.

- Are there upgradeable contracts? Which ones? What does the upgrade process look like?
The contracts are not upgradeable.


##  Roles

- What are the main roles of the system? Any permissioned role worth highlighting?
The owner of the contract can set various parameters like the 

- Can we assume whoever holds these roles is benevolent and always act in the well-being of the protocol and its users?
Yes

- Who holds the permissioned roles in reality? EOAs, multisig wallets, governance, etc.
Multisig wallet

- If there are centralized roles, are there any plans for progressive decentralization of the system? How would that look like?
We're currently working on an Open Zeppelin Governor contract with the Tally team to make progress towards these efforts.


##  Report

- What's your preferred format to have the report? Could be a single PDF, plain-text files, GitHub issues, etc.
Whatever is easiest for the auditor, we're not worried so much about a polished report.

- Is it necessary to deliver status reports as the audit progresses? How often?
No we trust the auditors will get the job done

- Are you planning to make the report public?
Depends on what we find 
