# Elixir Idiomatic Chronicle Client

Lets build an idiomatic client for Elixir for working with Chronicle.
Code should go into a `Source` folder at the root level.

The client should leverage the generated Elixir package that is built around
gRPC: https://hex.pm/packages/cratis/chronicle_contracts

However, we want to move the chronicle connection and chronicle connectionstring constructs
from the package to here in a namespace called connections, get it from the package code /Volumes/Code/Cratis/Chronicle/Source/Clients/Elixir.

The package should support the things that we have built for C#, but focus on leveraging
attributes as that is more idiomatic to Elixir, look at the conversation with Claude I had that concludes with how
this should be done.

The C# client is here: 
/Volumes/Code/Cratis/Chronicle/Source/Clients/DotNET

We also have a TypeScript client which you can learn from:
/Volumes/Code/Cratis/Chronicle.TypeScript

In this you can follow the Git history and see the evolution over the last couple of days and
build it for Elixir.

We're aiming for something that feels idiomatic Elixir.

We want to have whats correct with regards to API documentation.

Also, add a Samples folder with a console sample that I can run.
Also add a README at the root explaining how to get started with local development.

Set up a package that we can deploy with a proper publish pipeline, you can take inspiration
from the one we have already in chronicle for the contracts package: /Volumes/Code/Cratis/Chronicle/.github/workflows

We want the package name to be cratis/chronicle
