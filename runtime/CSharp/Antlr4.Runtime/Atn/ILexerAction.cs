// Copyright (c) Terence Parr, Sam Harwell. All Rights Reserved.
// Licensed under the BSD License. See LICENSE.txt in the project root for license information.

using Antlr4.Runtime;
using Antlr4.Runtime.Misc;
using Antlr4.Runtime.Sharpen;

namespace Antlr4.Runtime.Atn
{
    /// <summary>
    /// Represents a single action which can be executed following the successful
    /// match of a lexer rule.
    /// </summary>
    /// <remarks>
    /// Represents a single action which can be executed following the successful
    /// match of a lexer rule. Lexer actions are used for both embedded action syntax
    /// and ANTLR 4's new lexer command syntax.
    /// </remarks>
    /// <author>Sam Harwell</author>
    /// <since>4.2</since>
    public interface ILexerAction
    {
        /// <summary>Gets the serialization type of the lexer action.</summary>
        /// <returns>The serialization type of the lexer action.</returns>
        [NotNull]
        LexerActionType ActionType
        {
            get;
        }

        /// <summary>Gets whether the lexer action is position-dependent.</summary>
        /// <remarks>
        /// Gets whether the lexer action is position-dependent. Position-dependent
        /// actions may have different semantics depending on the
        /// <see cref="Antlr4.Runtime.ICharStream"/>
        /// index at the time the action is executed.
        /// <p>Many lexer commands, including
        /// <c>type</c>
        /// ,
        /// <c>skip</c>
        /// , and
        /// <c>more</c>
        /// , do not check the input index during their execution.
        /// Actions like this are position-independent, and may be stored more
        /// efficiently as part of the
        /// <see cref="ATNConfig.ActionExecutor()"/>
        /// .</p>
        /// </remarks>
        /// <returns>
        /// 
        /// <see langword="true"/>
        /// if the lexer action semantics can be affected by the
        /// position of the input
        /// <see cref="Antlr4.Runtime.ICharStream"/>
        /// at the time it is executed;
        /// otherwise,
        /// <see langword="false"/>
        /// .
        /// </returns>
        bool IsPositionDependent
        {
            get;
        }

        /// <summary>
        /// Execute the lexer action in the context of the specified
        /// <see cref="Antlr4.Runtime.Lexer"/>
        /// .
        /// <p>For position-dependent actions, the input stream must already be
        /// positioned correctly prior to calling this method.</p>
        /// </summary>
        /// <param name="lexer">The lexer instance.</param>
        void Execute([NotNull] Lexer lexer);
    }
}
