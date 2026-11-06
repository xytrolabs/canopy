#include "shell/bar/widgets/notification_widget_definition.h"

const shade::bar::WidgetDefinition<NotificationWidget::Options>& notificationWidgetDefinition() {
  using shade::bar::field;
  using Options = NotificationWidget::Options;

  static const shade::bar::WidgetDefinition<Options> definition{
      .type = "notifications",
      .fields = {
          field<&Options::hideWhenNoUnread>({
              .key = "hide_when_no_unread",
          }),
      },
  };
  return definition;
}
