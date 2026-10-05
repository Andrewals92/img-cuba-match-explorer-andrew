import {initBotId} from 'botid/client/core';
initBotId({protect:[
 {path:'/api/gateway',method:'POST',advancedOptions:{checkLevel:'basic'}},
 {path:'/api/match-assistant',method:'POST',advancedOptions:{checkLevel:'basic'}}
]});
