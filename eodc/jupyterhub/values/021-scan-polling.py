async def modify_pod_hook(spawner, pod):
    print("The image being used is:", spawner.image)

    import requests
    import base64
    import json
    import time

    image = spawner.image

    try:
        project = image.split("/")[1]
    except:
        return pod

    if project != "binderhub":
        spawner.add_event(
            eventTime=str(datetime.now(timezone.utc)),
            message="Image trusted, loading and starting server.",
            type="Normal",
            uid=f"trustedload",
        )

        return pod

    auth = "{{ harbor_api }}"

    base_url = (
        f"https://harbor.user.eopf.eodc.eu/api/v2.0/projects/{project}/repositories/"
    )

    repo_id = image.split("/")[2].split(":")[0]

    url_addon = "/artifacts?with_tag=true&with_scan_overview=true&with_sbom_overview=true&with_label=true&with_accessory=false&page_size=15&page=1"

    call_url = base_url + repo_id + url_addon

    response = requests.get(call_url, headers={"Authorization": f"Basic {auth}"})

    key = "application/vnd.security.vulnerability.report; version=1.1"

    timeout_s = 200
    wait_time_s = 0
    loaded = False

    spawner.add_event(
        eventTime=str(datetime.now(timezone.utc)),
        message="Scanning image for vulnerabilities, this might take a while.",
        type="Normal",
        uid=f"startscanload",
    )

    while wait_time_s < timeout_s:
        response = requests.get(call_url, headers={"Authorization": f"Basic {auth}"})
        decoded = json.loads(response.content.decode("utf-8"))[0]

        if "scan_overview" in decoded:
            status = decoded["scan_overview"][key]["scan_status"]
        else:
            status = "Unscanned"

        print(status)
        if status == "Success":
            loaded = True
            break

        elif status == "Running":
            message = ""
            spawner.add_event(
                eventTime=str(datetime.now(timezone.utc)),
                message=f"Scanning the built image for vulnerabilities. Current time: {wait_time_s}s (timeout {timeout_s}s)",
                type="Normal",
                uid=f"timeload{wait_time_s}",
            )

        wait_time_s += 5
        await asyncio.sleep(5)

    if not loaded:
        spawner.add_event(
            eventTime=str(datetime.now(timezone.utc)),
            message=f"Scanning timed out, aborting server start.",
            type="Normal",
            uid=f"timeoutload",
        )
        raise Exception("Failed Loading")

    spawner.add_event(
        eventTime=str(datetime.now(timezone.utc)),
        message="No critical vulnerabilities found, starting server.",
        type="Normal",
        uid=f"timeoutload",
    )

    return pod


c.Spawner.modify_pod_hook = modify_pod_hook
