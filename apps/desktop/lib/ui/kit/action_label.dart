/// Label of the button confirming an action: the label of the action
/// itself, without the ellipsis telling that it asks first (`Move…` is
/// confirmed by `Move`).
String actionLabel(String action) =>
    action.endsWith('…') ? action.substring(0, action.length - 1) : action;
