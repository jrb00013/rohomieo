/* Rohomieo elevated broker — shared pipe protocol (line-oriented ASCII).
 *
 * Pipe: \\.\pipe\RohomieoBroker
 * Request:  one line ending in \n
 * Response: "OK\n" or "ERR <message>\n"
 *
 * Commands (service runs as LocalSystem; client is unprivileged):
 *   PING
 *   FIREWALL_ADD
 *   FIREWALL_REMOVE
 *   DEFENDER_ADD <abs-path>
 *   DEFENDER_REMOVE <abs-path>
 *   START_HOST <abs-exe> [arg ...]
 *   START_SIGNALING <abs-exe> [arg ...]
 *   STOP_HOST
 *   STOP_SIGNALING
 *   KILL_ALL
 */
#pragma once

#define ROHOMIEO_BROKER_PIPE_NAME "\\\\.\\pipe\\RohomieoBroker"
#define ROHOMIEO_BROKER_SERVICE_NAME "RohomieoBroker"
#define ROHOMIEO_BROKER_DISPLAY_NAME "Rohomieo Elevated Broker"
#define ROHOMIEO_FIREWALL_RULE_NAME "Rohomieo-Signaling-TCP"
#define ROHOMIEO_FIREWALL_PORT "8443"
#define ROHOMIEO_ALLOWED_RUN_SUFFIX "\\AppData\\Local\\rohomieo-run"
#define ROHOMIEO_BROKER_PIPE_BUF 4096
