## 1. Module Update

- [x] 1.1 Remove `frequency` option from `checkTypes.<name>` submodule in `modules/nixos/services/service-jiraticketcreate.nix`
- [x] 1.2 Remove `timerCalendar` option from `checkTypes.<name>` submodule
- [x] 1.3 Add `schedule` option typed as `types.either (types.enum ["first_working_day_of_month" "first_working_day_of_quarter" "first_working_day_of_week" "every_working_day"]) (types.submodule { options.calendar = mkOption { type = types.str; }; })`
- [x] 1.4 Update `mkScript` to branch on `builtins.isString schedule`: structured path inlines `frequencyScript.${schedule}` and `is_trigger_day || exit 0`; calendar path omits the day-check entirely
- [x] 1.5 Update timer generation to use `OnCalendar = if builtins.isString instance.checkType.schedule then "daily" else instance.checkType.schedule.calendar`

## 2. Documentation

- [x] 2.1 Update options table in `docs/services/jiraticketcreate.md`: remove `frequency` and `timerCalendar` rows, add `schedule` row
- [x] 2.2 Update configuration example in `docs/services/jiraticketcreate.md` to use `schedule`
- [x] 2.3 Add migration note to `docs/services/jiraticketcreate.md` explaining the rename

## 3. Verification

- [x] 3.1 Run `nix build` to verify the module evaluates without errors
- [x] 3.2 Update CHANGELOG under `## NEXT VERSION` with the breaking change and migration instructions
