import time
import asyncio
from datetime import datetime, timezone
from kubespawner import KubeSpawner
from traitlets import List


class ExtendedSpawner(KubeSpawner):
    custom_event_queue = List(
        [],
        config=False,
        help="""
        Queue of custom events to be reported to the user on the spawn page.
        """,
    )

    _sent_custom_events = List(
        [],
        config=False,
        help="""
        List of uids of custom events that have been sent to the user.
        This is used to avoid sending the same event multiple times.
        """,
    )

    def add_event(self, eventTime, message, type, uid):
        """Add an event to the event queue

        This is used to add events that are not part of the normal
        kubernetes event stream, such as "Creating pod" or "Pod deleted"
        """
        if not self.events_enabled:
            return

        event = {
            "eventTime": eventTime,
            "lastTimestamp": eventTime,
            "message": message,
            "type": type,
            "involvedObject": {"name": self.pod_name},
            "metadata": {"uid": uid},
        }

        self.custom_event_queue.append(event)

    @property
    def events(self):
        """Filter event-reflector to just this pods events

        Returns list of all events that match our pod_name
        since our ._last_event (if defined).
        ._last_event is set at the beginning of .start().
        """
        if not self.event_reflector:
            return []

        events = []

        for event in self.event_reflector.events:

            if event["involvedObject"]["name"] != self.pod_name:
                # only consider events for my pod name
                continue

            if self._last_event and event["metadata"]["uid"] == self._last_event:
                # saw last_event marker, ignore any previous events
                # and only consider future events
                # only include events *after* our _last_event marker
                events = []

            else:
                events.append(event)

        for idx, event in self._sent_custom_events:
            events.insert(idx, event)

        for event in self.custom_event_queue:
            idx = len(events)
            events.append(event)
            self._sent_custom_events.append((idx, event))

        self.custom_event_queue = []

        return events


c.JupyterHub.spawner_class = ExtendedSpawner
