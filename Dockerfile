# syntax=docker/dockerfile:1

# ==============================================================================================================================================
# WillDemo Build
# ==============================================================================================================================================
ARG BUILD_IMAGE=build
FROM passivelogic/swift:jammy AS build-environment

FROM build-environment AS build
COPY Resources/docker/gitlab-known-hosts /root/.ssh/known_hosts

# On CI, override ssh git URLs with https and the injected token
# For adding additional repos that the token can access, see:
# https://docs.gitlab.com/ee/ci/jobs/ci_job_token.html#configure-the-job-token-scope-limit
ARG CI_JOB_TOKEN=
RUN test -n "${CI_JOB_TOKEN}" && git config --global url."https://gitlab-ci-token:${CI_JOB_TOKEN}@gitlab.com/PassiveLogic".insteadOf "git@gitlab.com:PassiveLogic" || true

WORKDIR /root/WillDemo
COPY Package.* .
RUN --mount=type=ssh swift package resolve

COPY Sources ./Sources
COPY Tests ./Tests
COPY Resources ./Resources
RUN --mount=type=ssh swift build -c release --static-swift-stdlib 

# ==============================================================================================================================================
# WillDemo
#
# Contains only the WillDemo binary.
# ==============================================================================================================================================

# needed glibc based linux for swift binary - ubuntu-24.04 - https://github.com/cruizba/ubuntu-dind
FROM cruizba/ubuntu-dind AS server

# Create the Swift library directory structure
RUN mkdir -p /usr/lib/swift/linux

# Copy ALL Swift dynamic libraries from the build container
COPY --from=build /usr/lib/swift/linux/*.so /usr/lib/swift/linux/

# Also copy libswiftDemangle.so from /usr/lib
COPY --from=build /usr/lib/libswiftDemangle.so /usr/lib/

# Copy libraries to standard locations as well for broader compatibility
COPY --from=build /usr/lib/swift/linux/*.so /usr/lib/

# Update the dynamic linker cache
RUN ldconfig

# Set library path environment variable
ENV LD_LIBRARY_PATH=/usr/lib/swift/linux:/usr/lib:$LD_LIBRARY_PATH

COPY --from=build /root/WillDemo/.build/release/WillDemo /usr/bin/WillDemo
COPY --from=build /root/WillDemo/Resources/docker/seccomp_profile.json /root/seccomp_profile.json
COPY --from=build /root/WillDemo/Resources/millrock.json /root/millrock.json

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]