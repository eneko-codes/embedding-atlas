# A model that needs remote code

Loading such a model executes code from its repository, with everything the run can reach. So the run that has the network never has the data, and the run that has the data never has the network.

1. **Fetch, with network and without data.** Download the model's repository into the Hugging Face cache without loading it: the Hub's own download command does this. Nothing of his is given to this run.
2. **Compute, with data and without network.** A second run that has no network, with the cache of step 1, `HF_HUB_OFFLINE=1` and `--trust-remote-code`. `HF_HUB_OFFLINE=1` only keeps the libraries from asking; it does not stop the model's code, so it does not replace a run with no network.

How a run is given no network is decided by whatever runs the tool. If the session cannot provide such a run, stop and tell him; never run step 2 with a network. If step 2 asks for the network, the model was not fully cached: repeat step 1.

Say in the reply that remote code ran, for which model, and that it ran without network.
