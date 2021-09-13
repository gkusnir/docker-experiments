# A tiny docker mount research

I am trying to clarify the behaviour of docker mounts of volumes and binds as I can not find any comprehensize documentation to that topic.
The docker official documentation is at least very humble. The tutorials are semi complete or even misleading. The stackoverflow answers are just aplicable to all observations and do not cover the topic completely.

## Experiment

1. Set up a simplistic docker image based on the following Dockefile
```dockerfile
FROM busybox:latest
VOLUME testvol1
COPY somefile.txt /testvol1/somefile.txt
```
2. Build a docker image `docker build -t test:1 .`

### First run

Run a docker container based on the generated image `docker run -ti --rm test:1`

Take a look at `mount` command inside the container
```
/ # mount
...
/dev/sda2 on /testvol1 type ext4 (rw,relatime,errors=remount-ro)
...
```

Note the following sections in inspect json
```json
    "HostConfig": {
        "Binds": null,

```

there is no `"Mounts"` section in `HostConfog`,

And there is this `Mounts` section in the root

```json
    "Mounts": [
        {
            "Type": "volume",
            "Name": "06de8495b6b142b49631a38df033a6a24da98e77e36adc9f80a2d1e85a666f0b",
            "Source": "/var/snap/docker/common/var-lib-docker/volumes/06de8495b6b142b49631a38df033a6a24da98e77e36adc9f80a2d1e85a666f0b/_data",
            "Destination": "testvol1",
            "Driver": "local",
            "Mode": "",
            "RW": true,
            "Propagation": ""
        }
    ],
```

The 'source' of this mount is accessible in host os and you can:
- create file in 'source' and will be visible in container
- change file contents and this will be also visible in the container
- create or change file in the container and the changes will be visible in the host os

This works as expected. Moreover the file added in the image creation process (somefile.txt) is copied to the volume when the container is initialized. So the content of the destination is available to the host os. This is also as expected and described in [documentation](https://docs.docker.com/engine/reference/builder/#volume): "The docker run command initializes the newly created volume with any data that exists at the specified location within the base image."


### Named volume

When you stop the container which was run with the `--rm` switch, the volume is deleted. Any changes made to it will be lost.

You can run the container without `--rm` switch and later reuse it, in this case the volume will be prserved, or you can create a named volume and use it. 

You cam create it like `docker volume create volume1` or just run `docker run -ti --rm --mount type=volume,source=volume1,destination=/testvol1 test:1`. Docker creates the volume automatically. inspecting the container will reveal the path of your volume in the host os.

After stopping the container or even removing the container, the volume is preserved and when the container is rerun later the volume is reused. Any files created on the volume remain on the volume.

If the volume (the folder in host os) is empty at the time docker starts the container, then *The docker run command initializes the newly created volume with any data that exists at the specified location within the base image* as stated in documentation. But if there is something in there, then this step is not done, so the files are kept as they are on the volume, which is good to keep state across container runs.

However if the desired changed state should be an empty folder, then this state is not kept as the initial step of *volume initialization* is done again.

If you created your docker image based on dockerfile above, than the behaviour you will experience is somewhat different and looks like buggy. 

The `mount` command inside the container shows something strange
```
/ # mount
...
/dev/sda2 on /testvol1 type ext4 (rw,relatime,errors=remount-ro)
/dev/sda2 on /testvol1 type ext4 (rw,relatime,errors=remount-ro)
...
```
a double entry of the folder mount.

There is no bind but there is a mount section
```json
    "HostConfig": {
        "Binds": null,

        "Mounts": [
            {
                "Type": "volume",
                "Source": "volume1",
                "Target": "/testvol1"
            }
        ],

```
and the mount section in the root shows two entries

```json
    "Mounts": [
        {
            "Type": "volume",
            "Name": "volume1",
            "Source": "/var/snap/docker/common/var-lib-docker/volumes/volume1/_data",
            "Destination": "/testvol1",
            "Driver": "local",
            "Mode": "z",
            "RW": true,
            "Propagation": ""
        },
        {
            "Type": "volume",
            "Name": "47a08e5ed5028f6f410c35989e5b8c6027c31c9af27e73025e6685d701aa87bf",
            "Source": "/var/snap/docker/common/var-lib-docker/volumes/47a08e5ed5028f6f410c35989e5b8c6027c31c9af27e73025e6685d701aa87bf/_data",
            "Destination": "testvol1",
            "Driver": "local",
            "Mode": "",
            "RW": true,
            "Propagation": ""
        }
    ],
```

Note the *destination* how it is different in slash.

This is probably not the intended behaviour. It is causing some weird situations:
- a file created inside container in `/testvol1` folder shows only in named volume (volume1) in os not the other one (47a08e5ed5028f6f410c35989e5b8c6027c31c9af27e73025e6685d701aa87bf in this case).
- creating a file in anonymous volume does not show up in the named volume nor in container.
- deleting somefile.txt in anonymous volume does not delete files in named nor in container.

So it looks like there is an extra anonymous volume created because of the definition of the line
```dockerfile
VOLUME testvol1
```
in dockerfile

This should be 
```dockerfile
VOLUME /testvol1
```

so let's correct the dockerfile and recreate the image

```dockerfile
FROM busybox:latest
VOLUME /testvol1
COPY somefile.txt /testvol1/somefile.txt
```

Now it works like expected.
In the following examples I will use the tag `test:2` for the second attempt to create an image. 

### Bind versus Volume

If you run docker with `docker run -ti --rm --mount type=volume,source=volume1,destination=/testvol1 test:2` it is equivalent to `docker run -ti --rm --mount source=volume1,destination=/testvol1 test:2` - so without the *type=volume*. According the [documentation](https://docs.docker.com/storage/volumes/#start-a-container-with-a-volume) this is equivalent to `docker run -ti --rm -v volume1:/testvol1 test:2`.

Running docker with `-v` option makes a different *inspect* json file. There is some bind in HostConfig section
```json
    "HostConfig": {
        "Binds": [
            "volume1:/testvol1"
        ],
```
and no mounts section, but there is the same mounts section in root
```json
    "Mounts": [
        {
            "Type": "volume",
            "Name": "volume5",
            "Source": "/var/snap/docker/common/var-lib-docker/volumes/volume1/_data",
            "Destination": "/testvol1",
            "Driver": "local",
            "Mode": "z",
            "RW": true,
            "Propagation": ""
        }
    ],
```

Despite the difference in *inspect* json there is no difference in behaviour.

### Adding another volume

Specifying another volume which has no in-container destination causes the destination to be created in the container. Running `docker run -ti --rm -v volume1:/testvol1 -v /testvol2 test:2` creates an anonymous volume and mounts it to /testvol2 in container which is created.


