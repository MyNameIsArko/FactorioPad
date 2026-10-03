-- The build and packaging scripts copy this over the game's freeplay script.
require('__base__/script/freeplay/control.lua')

-- The iOS keyboard has no Tab key to dismiss the freeplay intro dialog.
require('event_handler').add_lib({
  on_init = function()
    remote.call('freeplay', 'set_skip_intro', true)
  end,
  events = {
    [defines.events.on_tick] = function()
      if not storage.crash_site_cutscene_active then return end
      local player = game.get_player(1)
      if player and player.controller_type == defines.controllers.cutscene then
        -- Freeplay has already created the wreck and finished setting up the cutscene.
        player.exit_cutscene()
      end
    end
  }
})
