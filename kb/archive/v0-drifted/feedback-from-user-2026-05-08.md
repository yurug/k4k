I think we have a serious drift in this project, probably because we did not orient it well or because I was not clear enough.

You misunderstood the *level of autonomy of the coding agent* and this has a strong impact on the UX.

The user cares about *helping k4k* build the right software by
providing directions: the user describes informally a feature or a
property of the program, k4k asks questions to gradually refine this
demand into a non-ambiguous accurate specification. The interaction is
done using "cotype" on a single .k4k file. The level of accuracy we
are looking for: enough clarity to have a clear theorem denoting the
user informal demand. When this goal is achieved, the demand is
considered "stable", a "version" is defined and k4k will start
developing and verifying this version in *full autonomy*. Three possible situations at this stage:

1. The user modifies the .k4k file: it is notified that the decided version is under development so its change will be considered only when the new version is developed. The user can explicitly ask for k4k to stop the development of the current version and rollback to the previous one (second thoughts).

2. k4k is able to build the software new version and verify its correct.

3. k4k is not able to build the software because some unknown-unknowns have been discovered: it paused the development and mark the .k4k file as unstable, with questions for the user. Once the file is back to stability, the development is unpaused.


I want to insist: that's all the user does. The user only interacts
with k4k by writing in the shared .k4k file: no configurations, no
commands, no other files need to be considered by the user. This means
k4k must be autonomous to set up the development and verification
tooling itself depending on the tools that have chosen to conduct the
verification. 
