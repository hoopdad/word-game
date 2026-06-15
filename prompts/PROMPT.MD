/fleet You are now in fleet mode. Dispatch sub-agents (via the task tool) in parallel to do the work.

Goals for this sprint:
 - Deliver user-web-ui value with staged orchestration, parallel fan-out, artifact handoffs, gated progression, and bounded remediation loops.
 - Build and deploy the application defined here. 
 - Success means an application, fully deployed in Azure with all requirements and user flows met.

Outcome is a multiplayer, distributed game. Anyone loading the website before a game starts can participate. Only one game is active at a time in the entire system. 

- If a user joins after the game begins, the user will see "Game in progress. Please wait." and their screen will poll the system until they are eligible to play.
- When a user first joins they will not see the dashboard. They must set a name. If others in the system have chosen the same name, tell them "that name is taken. and they must choose another. Once they choose a unique name, they will see the dashboard.
- The names of all active users are displayed on the main dashboard.
- The count of all games ever played is shown on the dashboard.
- The top 10 highest scoring players of all time and the top 3 of today are shown on the dashboard.
- A button to start a game is shown. If any user clicks that button, the game begins and all users are included. 
- The game begins with a screen that says "gathering categories". That shows as long as the Category agent is working.
- The category agent, a Foundry agent with access to the internet, will in parallel connect to all the websites lsited in its configuration table. (That configuraiton table is configurable via a link on the dashbaord that says "configure categories").
- The category agent will read the contents of the web pages and determine 1 or more categories of words or 2-3 word phrases specific to that category. For example, going to "https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-highlyavailable" will find words like {"highly available","VPN","VPN Gateway","S2S VPN"} which can be gruoped into "". The agent should only include non general words; articles, prepositions, etc might be part of a phrase but not a single word. "A" is not valid but "A Long Winter's Night" might go with a category "Christmas".
- The game begins with an overview of the categories that will be used. There will be one category per user. A button the category view starts the first round.
- At the begining of every round, users are assigned roles randomly. Exactly one user will be named as the guesser. The other players will be named as clue-givers. Users are shown their role, then a countdown from 10 seconds to 0 is shown to all. 
- The game works in rounds. A round is a group of one or more guesses that occur during a 2 minute period. A guess is when the clue-givers are shown the word and the guesser has to guess it. When the gueser is correct, as judged by any clue-giver, the guesser sees the word on their screen for 3 seconds, and gets 10 points for the word. After a correct guess but beffore the 3 seconds, another word is shown to clue-givers and the guesser's screen shows no word. If time expires before the guess is correct, 0 points are awarded and the round will end.
- At the end of the round, the score is saved to the database. The system will randomly pick a user who has not yet been a guesser. If all the users have been guessers in this session, the game ends.
- At the end of the game, the winner or winners are shown on the screen. The winner is the user with the most points during that game. If any of the daily or all-time high scores are beaten, then the all time and today's top scores should be updated accordingly.
- After the end of the game, the dashboard resets to pre-game mode with the cards and buttons as defined earlier. A status bar will celebrate the winner(s) of the last game.
- Refer to nfr.yml and external-user-pattern.md for additional requirements. 
- Build GitHub Actions for CI and CD functions for web, api, Foundry agent, and infrastructure. Infrastructure must deploy successfully before the others. Success means the CI/CD Actions have deployed the entire application, it is functional, and users can log in with Entra External ID.
